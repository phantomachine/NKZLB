% growthpf.m
% Main file for computing the policy functions in the stochastic growth model
% Written by Takeki Sunakawa
% Last updated: May 28 2018

clear all;
rng('default');

% metaparameters
%pfmethod = 0; % =0: TI, =1: future PEA, =2: current PEA 
np = 2; % order of polynomial, 2 or 4
ngh = 3; % number of gh nodes
tol = 1e-8; % tolerance for main loop
simT = 10000; % length of simulation for Euler error

% parameter values
% tau = 5.0;
beta = 0.99;
alpha = 1/3;
delta = 0.1/4;
rhoz = 0.95;
sigmaz = 0.008;

tauvec = [1.0 2.0 5.0]';

% for i=1:size(tauvec,1)
% 
%     tau = tauvec(i);
%     disp(' ');
%     disp(sprintf(' tau = %1.1f',tau));
%     disp(' order of polynomial, np=2');
    tau = 1.0;
    %pfmethod = 0; % =0: TI, =1: future PEA, =2: current PEA 
    simresult11 = growthpf(0,4,ngh,tol,simT,tau,beta,alpha,delta,rhoz,sigmaz)
%     simresult12 = growthpf(1,2,ngh,tol,simT,tau,beta,alpha,delta,rhoz,sigmaz);
%     simresult13 = growthpf(2,2,ngh,tol,simT,tau,beta,alpha,delta,rhoz,sigmaz);
% 
%     disp(' ');
%     disp(' order of polynomial, np=4');
%     simresult21 = growthpf(0,4,ngh,tol,simT,tau,beta,alpha,delta,rhoz,sigmaz);
%     simresult22 = growthpf(1,4,ngh,tol,simT,tau,beta,alpha,delta,rhoz,sigmaz);
%     simresult23 = growthpf(2,4,ngh,tol,simT,tau,beta,alpha,delta,rhoz,sigmaz);
% 
%     filename = ['simresult' num2str(i) '.csv'];
%     csvwrite(filename,[simresult11;simresult12;simresult13;simresult21;simresult22;simresult23]);
% 
% end


function simresult = growthpf(pfmethod,np,ngh,tol,simT,tau,beta,alpha,delta,rhoz,sigmaz)

tic;

%% setups
cflag = 1; % =1: cross terms are on, =0: cross terms are off
ns = 2; % number of variables
if (cflag==1)
    nv = (np+1)^ns; % number of grid points
else
    % if cross terms are off
    nv = 1 + np*ns;
end

% steady state values
kss = ((1/beta-1+delta)/alpha)^(1/(alpha-1));
css = kss^alpha-delta*kss;
fss = (alpha*kss^(alpha-1)+1-delta)*(1/css)^tau;

% set up grid points
kmin = 0.8*kss;
kmax = 1.2*kss;
zmin = -3*sigmaz/sqrt(1-rhoz^2);
zmax = 3*sigmaz/sqrt(1-rhoz^2);

xgrid = zeros(ns,nv);

if (np==2)

    for i=1:ns
        xgrid(i,np*(i-1)+2) = -1.0;
        xgrid(i,np*(i-1)+3) = 1.0;
    end
    
    if (cflag==1)
        % cross terms
        xgrid(1,[6 8]) = -1.0;
        xgrid(1,[7 9]) = 1.0;
        xgrid(2,6:7) = -1.0;
        xgrid(2,8:9) = 1.0;
    end
    
elseif (np==4)

    for i=1:ns
        xgrid(i,np*(i-1)+2) = -1.0;
        xgrid(i,np*(i-1)+3) = 1.0;
        xgrid(i,np*(i-1)+4) = -1.0/sqrt(2.0);
        xgrid(i,np*(i-1)+5) = 1.0/sqrt(2.0);
    end
    
    if (cflag==1)
        % cross terms
        xgrid(1,[10 14 18 22]) = -1.0;
        xgrid(1,[11 15 19 23]) = 1.0;
        xgrid(1,[12 16 20 24]) = -1.0/sqrt(2.0);
        xgrid(1,[13 17 21 25]) = 1.0/sqrt(2.0);
        xgrid(2,10:13) = -1.0;
        xgrid(2,14:17) = 1.0;
        xgrid(2,18:21) = -1.0/sqrt(2.0);
        xgrid(2,22:25) = 1.0/sqrt(2.0);
    end
    
end

kgrid = (kmax-kmin)/2*xgrid(1,:) + (kmax+kmin)/2;
zgrid = (zmax-zmin)/2*xgrid(2,:) + (zmax+zmin)/2;

for i = 1:nv

    if (np==2)
        bbt(i,:) = poly2(xgrid(1,i),xgrid(2,i),cflag);
    elseif (np==4)
        bbt(i,:) = poly4(xgrid(1,i),xgrid(2,i),cflag);
    end
    
end

bbtinv = inv(bbt);

slopecon = zeros(ns,2);
slopecon(1,1) = 2/(kmax-kmin);
slopecon(1,2) = -(kmax+kmin)/(kmax-kmin);
slopecon(2,1) = 2/(zmax-zmin);
slopecon(2,2) = -(zmax+zmin)/(zmax-zmin);

% Gaussian-Hermite quadrature
% xz is abscissa and wz is weight for eps
[xz,wz] = qnwnorm(ngh,0,sigmaz);

if (pfmethod==2)
    % precomputation of integrals a la Judd et al.
    xzpe = prenormchev(slopecon(2,:),np,zgrid,rhoz,sigmaz);
end

% initial values
cvec0 = css*ones(nv,1);
cvec1 = zeros(nv,1);
kvec0 = kss*ones(nv,1);
kvec1 = zeros(nv,1);
fvec0 = fss*ones(nv,1);
fvec1 = zeros(nv,1);

%% main loop
diff = 1e+4;
iter = 0;

% the loop continues until the norm between the old and new policy functions is sufficiently small
while (diff>tol) 
    
    % fitting polynomials
    % the basis function matrix (bbtinv is its inverse) is fixed with the collocation points
    % and precomputed, but data points (cvec or fvec) will change over iterations.
    if (pfmethod==0)
        % time iteration
        % the coefficients (theta) for the policy function of c
        coefc = bbtinv*cvec0;
    else
        % future or current PEA
        coeff = bbtinv*fvec0;
    end

    for i=1:nv % index for the grid points

        % at each grid point, we pick up (k_j,z_m)
        znow = zgrid(i);
        know = kgrid(i);
        
        % time iteration
        if (pfmethod==0)

            % solve nonlinear equation for c
            % f(k,z)
            yterm = exp(znow)*know^alpha + (1-delta)*know;
            % use Chris Sims' csolve for nonlinear optimization
            % i.e., solve R(c)=0 for c given k_j, z_m, and theta
            c0 = csolve('foc',cvec0(i),[],tol^2,100,yterm,znow,coefc,slopecon,np,cflag,xz,wz,tau,beta,alpha,delta,rhoz);        
            kp = yterm - c0;
            % expectation term (not necessary)
            f0 = beta*(alpha*exp(znow)*know^(alpha-1)+1-delta)*(1/c0)^tau;
                    
        % future PEA
        elseif (pfmethod==1)

            % current period's c (obtained by current period's f)
            c0 = fvec0(i)^(-1/tau);
            yterm = exp(znow)*know^alpha + (1-delta)*know;
            kp = yterm - c0;

            % update the expectation term f with interpolation
            xkp = slopecon(1,1)*kp + slopecon(1,2); % k to x in [-1,1]
            % numerical integral with GH quadrature
            % xz is abscissa and wz is weight for eps
            f0 = 0.0;
            for igh=1:ngh

                % next period's f (obtained by interpolation)
                zp = rhoz*znow + xz(igh);
                xzp = slopecon(2,1)*zp + slopecon(2,2); % z to x in [-1,1]
                if (np==2)
                    fp = poly2(xkp,xzp,cflag)*coeff;
                elseif (np==4)
                    fp = poly4(xkp,xzp,cflag)*coeff;
                end
                % next period's c (obtained by next period's f)
                cp = fp^(-1/tau);
                % current period's f
                f0 = f0 + wz(igh)*beta*(alpha*exp(zp)*kp^(alpha-1)+1-delta)*(1/cp)^tau;

            end
            
        % current PEA
        elseif (pfmethod==2)

            % successive approximation for kp
            kp = kvec0(i);
            xkp = slopecon(1,1)*kp + slopecon(1,2); % k to x in [-1,1]
            % precomputation of integrals
            % xzpe have integral of basis functions T_j(xp) for j = 1,2,... where xp = d0 + d1*zp at each
            % grid point i=1,...,nv
            
            % calculate the current f with interpolation
            if (np==2)
                f0 = poly2precomp(xkp,xzpe(:,i)',cflag)*coeff;
            elseif (np==4)
                f0 = poly4precomp(xkp,xzpe(:,i)',cflag)*coeff;
            end

            c0 = f0^(-1/tau);
            yterm = exp(znow)*know^alpha + (1-delta)*know;
            kp = yterm - c0;

            % update the current f by using current c, k and z
            f0 = beta*(alpha*exp(znow)*know^(alpha-1)+1-delta)*(1/c0)^tau;
                        
        end
        
        % represent the new policy function at each grid point i
        cvec1(i) = c0;
        kvec1(i) = kp;
        fvec1(i) = f0;
        
    end
    
    % calculate the norm between the old and new policy functions
    diffc = max(abs(cvec1-cvec0));
    diffk = max(abs(kvec1-kvec0));
    diff = max([diffc diffk]);

    % update the policy functions
    cvec0 = cvec1;
    kvec0 = kvec1;
    fvec0 = fvec1;
    
    % counter for iterations
    iter = iter + 1;

    % show the convergence pattern
    disp([iter diff]);
    
end

t = toc;
% end of main loop

%% Euler errors
drop = floor(0.05*simT);
simTT = simT + drop;

coefc = bbtinv*cvec0;
coeff = bbtinv*fvec0;

kvec = zeros(simTT,1);
zvec = zeros(simTT,1);
evec = zeros(simTT,1);
kvec(1) = kss;
zvec(1) = 0.0;
rng(0);

for time = 1:simTT-1
    
    know = kvec(time);
    znow = zvec(time);
    yterm = exp(znow)*know^alpha + (1-delta)*know;
    
    % policy function
    xknow = slopecon(1,1)*know + slopecon(1,2);
    xznow = slopecon(2,1)*znow + slopecon(2,2);

    % TI
    if (pfmethod==0)
        
        if (np==2)
            c0 = poly2(xknow,xznow,cflag)*coefc;
        elseif (np==4)
            c0 = poly4(xknow,xznow,cflag)*coefc;
        end

    % future PEA
    elseif (pfmethod==1)

        if (np==2)
            f0 = poly2(xknow,xznow,cflag)*coeff;
        elseif (np==4)
            f0 = poly4(xknow,xznow,cflag)*coeff;
        end
        
        c0 = f0^(-1/tau);
        
    % current PEA
    elseif (pfmethod==2)

        % precomputation of integrals
        xzpe = prenormchev(slopecon(2,:),np,znow,rhoz,sigmaz);        
        if (np==2)
            c0 = poly2(xknow,xznow,cflag)*coefc;
            kp = yterm - c0;
            xkp = slopecon(1,1)*kp + slopecon(1,2);
            f0 = poly2precomp(xkp,xzpe',cflag)*coeff;
        elseif (np==4)
            c0 = poly4(xknow,xznow,cflag)*coefc;
            kp = yterm - c0;
            xkp = slopecon(1,1)*kp + slopecon(1,2);
            f0 = poly4precomp(xkp,xzpe',cflag)*coeff;
        end

        c0 = f0^(-1/tau);
        
    end
        
    % Euler errors
    kp = yterm - c0;
    xkp = slopecon(1,1)*kp + slopecon(1,2);
    
    f0 = 0.0;
    for igh=1:ngh

        % NOTE: numerical integration is used for zp for all the methods
        zp = rhoz*znow + xz(igh);
        xzp = slopecon(2,1)*zp + slopecon(2,2);
        
        if (pfmethod==0)
        
            if (np==2)
                cp = poly2(xkp,xzp,cflag)*coefc;
            elseif (np==4)
                cp = poly4(xkp,xzp,cflag)*coefc;
            end

        elseif (pfmethod==1)

            zp = rhoz*znow + xz(igh);
            xzp = slopecon(2,1)*zp + slopecon(2,2);
            if (np==2)
                fp = poly2(xkp,xzp,cflag)*coeff;
            elseif (np==4)
                fp = poly4(xkp,xzp,cflag)*coeff;
            end

            cp = fp^(-1/tau);

        elseif (pfmethod==2)

            % precomputation of integrals
            xzppe = prenormchev(slopecon(2,:),np,zp,rhoz,sigmaz);        
            if (np==2)
                cp = poly2(xkp,xzp,cflag)*coefc;
                kpp = yterm - cp;
                xkpp = slopecon(1,1)*kpp + slopecon(1,2);
                fp = poly2precomp(xkpp,xzppe',cflag)*coeff;
            elseif (np==4)
                cp = poly4(xkp,xzp,cflag)*coefc;
                kpp = yterm - cp;
                xkpp = slopecon(1,1)*kpp + slopecon(1,2);
                fp = poly4precomp(xkpp,xzppe',cflag)*coeff;
            end

            cp = fp^(-1/tau);

        end
        
        f0 = f0 + wz(igh)*(alpha*exp(zp)*kp^(alpha-1)+1-delta)*(1/cp)^tau;

    end
    
    enow = 1 - (c0^tau)*beta*f0;
    
    kvec(time+1) = kp;
    zvec(time+1) = rhoz*znow + sigmaz*randn;
    evec(time+1) = enow;
    
end

evec = evec(drop+1:simTT);
simresult = [log10(mean(abs(evec))) log10(max(abs(evec))) t];
disp(simresult);

end    
