function LCVout = run_LCV( ell,Z1,Z2,crosstrait_intercept,ldsc_intercept,weights,sig_threshold,...
    no_blocks,cross_int,n1,n2)
%RUN_LCV runs LCV on summary statistics for two traits.
%   INPUT VARIBLES: ell, Mx1 vector of LD scores; Z1, Mx1 vector of
%   estimated marginal per-normalized-genotype effects on trait 1
%   (or Z scores; invariant to scaling); Z2, Mx2 vector of effects on trait
%   2; crosstrait_intercept, 0 if cohorts are disjoint, 1 if cohorts are
%   possibly nondisjoint and necessary correction is unknown, 2 if cohorts
%   are nondisjoint with known overlap and phenotypic covariance;
%   ldsc_intercept, 0 if intercept should be fixed and 1 otherwise;
%   weights, Mx1 vector of regression weights; sig_threshold, threshold
%   above which to discard chisq statistics for the purpose of estimating
%   the LDSC intercept if they are above sig_threshold*mean_chisq;
%   no_blocks, number of jackknife blocks.
%   OPTIONAL INPUT VARIBLES:  n1,
%   1/var(Z1), only needed if ldsc_intercept=1; n2, 1/var(Z2); noisecorr,
%   covariance between sampling errors for Z1 and Z2, only needed if
%   crosstrait_intercept=2 (if zero, equivalent to setting
%   crosstrait_intercept=0).
%   OUTPUT VARIABLES: zsc_asym, Z score for partial genetic causality;
%   gcp_est, posterior mean gcp; gcp_err, posterior standard dev; rho, 
%   estimated genetic correlation; rho_err, standard error of rho estimate;
%   CI_pval, approx likelihood for gcp on [-1:.01:1]; p_fullcausal1,
%   p-value for null that gcp=-1; p_fullcausal2, p-value for null that
%   gcp=1; k41, estimate of E(alpha1^3 alpha2); k42, estimate of
%   E(alpha2^3 alpha1); s, 1x2 vector of normalizations used for Z1, Z2,
%   proportional to sqrt(h2g); s_err, standard err of s; intercept,
%   1x3 vector containing trait 1 LDSC intercept, trait 2 LDSC intercept
%   and crosstrait intercept respectively.

if nargin<3
    error('Please provide at least 3 input arguments: LD scores and Z scores or effect-size estimates for each trait')
end
[mm,kk]=size(ell);
if kk~=1
    error('LD scores should be an Mx1 vector')
end
[m2,kk]=size(Z1);
if kk~=1 || m2~=mm
    error('Z scores should be Mx1 vectors')
end
[m2,kk]=size(Z2);
if kk~=1 || m2~=mm
    error('Z scores should be Mx1 vectors')
end

if ~exist('crosstrait_intercept')
    crosstrait_intercept=1;
end

if ~exist('ldsc_intercept')
    ldsc_intercept=1;
end

if ~exist('weights')
    weights=1./max(1,ell);
end

if ~exist('sig_threshold')
    sig_threshold=inf; %Set to e.g. 30 in order to exclude GWS SNPs when computing LDSC intercept
end

if ~exist('no_blocks')
    no_blocks=100;
end

if ~exist('n1') && ldsc_intercept==0 
    n1=1;
end

if ~exist('n2') && ldsc_intercept==0 
    n2=1;
end

grid=-1:.01:1;

%% Estimate mixed 4th moments for each jackknife block
intercept_jk=zeros(no_blocks,1);asym_jk1=zeros(no_blocks,1);asym_jk2=asym_jk1;rho_jk=asym_jk1;s1jk=rho_jk;s2jk=rho_jk;
blocksize=floor(length(Z1)/no_blocks);intercept1_jk=rho_jk;intercept2_jk=rho_jk;

if ldsc_intercept
    for jk=1:no_blocks
        ind=[1:(jk-1)*blocksize, jk*blocksize+1:length(Z1)];
        [ rho_jk(jk),asym_jk1(jk),asym_jk2(jk),intercept_jk(jk),s1jk(jk),s2jk(jk),intercept1_jk(jk),intercept2_jk(jk)] = ...
            estimate_k4( ell(ind,:),Z1(ind),Z2(ind),crosstrait_intercept,ldsc_intercept,weights(ind),sig_threshold  );
        
    end
else
    for jk=1:no_blocks
        ind=[1:(jk-1)*blocksize, jk*blocksize+1:length(Z1)];
        [ rho_jk(jk),asym_jk1(jk),asym_jk2(jk),intercept_jk(jk),s1jk(jk),s2jk(jk),intercept1_jk(jk),intercept2_jk(jk)] = ...
            estimate_k4( ell(ind,:),Z1(ind),Z2(ind),crosstrait_intercept,ldsc_intercept,weights(ind),sig_threshold,n1,n2,cross_int  );
    end
end
intercept=[mean(intercept1_jk) mean(intercept2_jk) mean(intercept_jk)];

rho=mean((rho_jk));
rho_err=std((rho_jk))*sqrt(no_blocks+1);
flip=sign(rho);

s=[mean((s1jk)), mean((s2jk))];
s_err=[std((s1jk)), std((s2jk))]*sqrt(no_blocks+1);

asym_jk1=asym_jk1-3*rho_jk;
asym_jk2=asym_jk2-3*rho_jk;


%% Point estimate + CI
likelihood=zeros(1,length(grid));
for kk=1:length(grid) % Loop over possible gcp values
    xx=grid(kk);
    fx=abs(rho_jk).^(-xx);
    numer=asym_jk1./fx-fx.*asym_jk2;
    denom=max(1./abs(rho_jk),sqrt(asym_jk1.^2./fx.^2+fx.^2.*asym_jk2.^2));
    pct_diff_jk=numer./denom;% S(xx) statistic for each jackknife block
    est_err=std(pct_diff_jk)*sqrt(no_blocks+1); % std err of S(xx)
    
    likelihood(kk)=tpdf(real(mean(pct_diff_jk)/est_err),no_blocks-2);
    if kk==1 % test for gcp=-1
        p_fullcausal2=tcdf(-flip*(mean(pct_diff_jk)/est_err),no_blocks-2);
    elseif kk==length(grid) % test for gcp=1
        p_fullcausal1=tcdf(flip*(mean(pct_diff_jk)/est_err),no_blocks-2);
    elseif xx==0 % test for gcp=0
        zsc_asym=flip*mean(pct_diff_jk)/est_err;
        
    end
end

p_gcpzero_2tailed=tcdf(-abs(zsc_asym),no_blocks-2)*2;

gcp_est=sum(likelihood.*grid)./sum(likelihood); % posterior mean
gcp_err=sqrt(sum(likelihood.*grid.^2)./sum(likelihood)-gcp_est.^2); % posterior err

% Warnings for poorly significant or negative h2g estimates
if ~isreal(rho)
    warning('Negative heritability estimates leading to unstable results and false positives')
elseif any(s./s_err<4)
    warning('Very noisy heritability estimates potentially leading to false positives')
elseif any(s./s_err<7)
    warning('Borderline noisy heritability estimates potentially leading to false positives')
end

% Warning for non-significant rho_g
if abs(rho/rho_err)<2
    warning('No significantly nonzero genetic correlation, potentially leading to conservative p-values')
end

LCVout(1).zscore=zsc_asym;
LCVout(1).pval_gcpzero_2tailed=p_gcpzero_2tailed;
LCVout(1).gcp_pm=gcp_est;
LCVout(1).gcp_pse=gcp_err;
LCVout(1).rho_est=rho;
LCVout(1).rho_err=rho_err;
LCVout(1).pval_fullycausal=[p_fullcausal1 p_fullcausal2];
LCVout(1).h2_zscore=s./s_err;
LCVout(1).likelihood=likelihood;

end

