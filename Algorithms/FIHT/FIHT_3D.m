function [si,iter,ratio,x]=FIHT_3D(obs,n1,n2,n3,r,K,maxit,tol,trace)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%Fast iterative hard thresholding algrotihm for 3D spectrally sparse signals.
%
%Inputs
% obs: 1D vector that stores the observed samples. 
% n1: first dimension of the full signal to be reconstructed.
% n2: second dimension of the full signal to be reconstructed.
% n3: third dimension of the full signal to be reconstructed.
% r: model order of the signal.
% K: indecies for the observed samples in the original signal, obs and K
% should be correspoding to each other.
% maxit: maximum number of iterations allowed (suggested value: 500).
% tol: the iteration scheme is terminated when the relative ratio between 
% successive iterates fall below this value (suggested value: 1e-5).
% trace (optional): if not zero, the relative error after each iteation
% is displayed.
% 
%Outputs
% si: indicator of success, return 1 when the relative ratio falls below tol 
% within maxit iteratsions.
% iter: number of iterations executed.
% ratio: relative ratio after iter iterations.
% x: reconstructed signal.
%
%Example
% [K,ox,f]=generate_signal([32 32 16],5,1024);obs=ox(K);
% [si,iter,ratio,x]=FIHT_3D(obs,32,32,16,5,K,500,1e-5,1);
%
%Reference: Cai, J. F., Wang, T., & Wei, K. (2016). Fast and Provable 
%Algorithms for Spectrally Sparse Signal Reconstruction via Low-Rank Hankel
%Matrix Completion. arXiv preprint arXiv:1606.01567.
%
%Last modified: 15-March-2017
%Please email tianming-wang@uiowa.edu for bug report.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if ~exist('trace','var')
    trace=0;
end

si=0; % success indicator

if mod(n1,2)
    p1=(n1+1)/2;
    d1=[1:p1 p1-1:-1:1]';
else
    p1=n1/2;
    d1=[1:p1 p1 p1-1:-1:1]';
end
if mod(n2,2)
    p2=(n2+1)/2;
    d2=[1:p2 p2-1:-1:1]';
else
    p2=n2/2;
    d2=[1:p2 p2 p2-1:-1:1]';
end
if mod(n3,2)
    p3=(n3+1)/2;
    d3=[1:p3 p3-1:-1:1]';
else
    p3=n3/2;
    d3=[1:p3 p3 p3-1:-1:1]';
end

DD=kron(d3,kron(d2,d1));
DD=reshape(DD,n1,n2,n3);

q1=n1+1-p1;
q2=n2+1-p2;
q3=n3+1-p3;

l1=p1*p2*p3;
l2=q1*q2*q3;

epsilon=eps(l1*l2);

ratio=zeros(maxit,1);

% indecies pre-computed for fhmvmultiply_3D to use
ind1=zeros(l2,1);
for i=1:q3
    ix=(i-1)*q1*q2;
    ixx=(i-1)*n1*n2;
    for j=1:q2
        ind1(ix+(j-1)*q1+1:ix+j*q1)=ixx+(j-1)*n1+1:ixx+(j-1)*n1+q1;
    end
end
ind2=zeros(l1,1);
for i=1:p3
    iy=(i-1)*p1*p2;
    iyy=(q3+i-2)*n1*n2;
    for j=1:p2
        ind2(iy+(j-1)*p1+1:iy+j*p1)=iyy+(q2+j-2)*n1+q1:iyy+(q2+j-1)*n1;
    end
end

% Initialization via one step hard thresholding
N=n1*n2*n3;
m=length(obs); % number of observed samples

alpha=N/m;
b=alpha*obs;

x=zeros(n1,n2,n3); % the full signal to be reconstructed
x(K)=b;

opts=[];opts.eta=1e-16; % set tolerance for lansvd

if mod(n1,2) && mod(n2,2) && mod(n3,2)
    
    Yforward=@(z) fhmvmultiply_3D(x,z,q1,q2,q3,ind1,ind2);
    Ytranspose=@(z) fhmvmultiply_3D(conj(x),z,p1,p2,p3,ind1,ind2);
    [U,S,V]=lansvd(Yforward,Ytranspose,l1,l2,r,'L',opts);
    s=diag(S);
    
    gamma=-(angle(U(1,:))+angle(V(1,:)))/2;
    if r==1
        U=U*exp(1i*gamma);
    else
        U=U*sparse(1:r,1:r,exp(1i*gamma));
    end
    
    x=zeros(n1,n2,n3);
    for i=1:r
        ui=reshape(U(:,i),p1,p2,p3);
        x=x+s(i)*conv_fft(ui,ui);
    end
    x=x./DD;
 
    HxUc=zeros(l1,r);
    Z=zeros(r,r);
    
    % Iterations
    for iter=1:maxit
        
        x_old=x;
        
        x(K)=b+(1-alpha)*x(K); % gradient descent with step size alpha
        
        Uc=conj(U);
        
        for i=1:r
            uic=Uc(:,i);
            HxUc(:,i)=fhmvmultiply_3D(x,uic,q1,q2,q3,ind1,ind2);
        end
        
        C=(U')*HxUc;
        X=HxUc-U*C;
        [Q,R]=qr(X,0);
        M=[C R.';R Z];
        
        [Uc,S,Vc]=svd(M);
        s=diag(S(1:r,1:r));

        srev=s(r:-1:1);
        r=r-sum(cumsum(srev)/sum(s)<epsilon);

        Uc=Uc(:,1:r);
        Vc=Vc(:,1:r);
        
        gamma=-(angle(Uc)+angle(Vc));
    	Uc=Uc.*sqrt(exp(1i*gamma));
        U=[U Q]*Uc;
        
        x=zeros(n1,n2,n3);
        for i=1:r
            ui=reshape(U(:,i),p1,p2,p3);
            x=x+s(i)*conv_fft(ui,ui);
        end
        x=x./DD;
        
        ratio(iter)=norm(x(:)-x_old(:))/norm(x_old(:));
    
        if trace
            fprintf('Iteration %4d, RMSE = %.10f \n',iter,ratio(iter))
        end
        
        if ratio(iter)<tol
            si=1;
            ratio=ratio(1:iter);
            break;
        elseif ratio(iter)>1
            break;
        end
        
    end

else
    
    ind3=zeros(l1,1);
    for i=1:p3
        ix=(i-1)*p1*p2;
        ixx=(i-1)*n1*n2;
        for j=1:p2
            ind3(ix+(j-1)*p1+1:ix+j*p1)=ixx+(j-1)*n1+1:ixx+(j-1)*n1+p1;
        end
    end    
    ind4=zeros(l2,1);
    for i=1:q3
        iy=(i-1)*q1*q2;
        iyy=(p3+i-2)*n1*n2;
        for j=1:q2
            ind4(iy+(j-1)*q1+1:iy+j*q1)=iyy+(p2+j-2)*n1+p1:iyy+(p2+j-1)*n1;
        end
    end
    
    Yforward=@(z) fhmvmultiply_3D(x,z,q1,q2,q3,ind1,ind2);
    Ytranspose=@(z) fhmvmultiply_3D(conj(x),z,p1,p2,p3,ind3,ind4);
    [U,S,V]=lansvd(Yforward,Ytranspose,l1,l2,r,'L',opts);
    s=diag(S);
    
    x=zeros(n1,n2,n3);
    for i=1:r
        ui=reshape(U(:,i),p1,p2,p3);
        vi=reshape(V(:,i),q1,q2,q3);
        x=x+s(i)*conv_fft(ui,conj(vi));
    end
    x=x./DD;
        
    UtHx=zeros(r,l2);
    HxV=zeros(l1,r);
    Z=zeros(r,r);
    
    % Iterations
    for iter=1:maxit
        
        x_old=x;
        
        x(K)=b+(1-alpha)*x(K); % gradient descent with step size alpha
        
        for i=1:r
            ui=U(:,i);
            UtHx(i,:)=(fhmvmultiply_3D(conj(x),ui,p1,p2,p3,ind3,ind4))';
            vi=V(:,i);
            HxV(:,i)=fhmvmultiply_3D(x,vi,q1,q2,q3,ind1,ind2);
        end
       
        C=UtHx*V;
        Xt=UtHx-C*(V');
        X=Xt';
        Y=HxV-U*C;   
        [Q1,R1]=qr(X,0);
        [Q2,R2]=qr(Y,0);
        M=[C R1';R2 Z];
        
        [Uc,S,Vc]=svd(M);
        s=diag(S(1:r,1:r));

        srev=s(r:-1:1);
        r=r-sum(cumsum(srev)/sum(s)<epsilon);

        U=[U Q2]*Uc(:,1:r);
        V=[V Q1]*Vc(:,1:r);
        
        x=zeros(n1,n2,n3);
        for i=1:r
            ui=reshape(U(:,i),p1,p2,p3);
            vi=reshape(V(:,i),q1,q2,q3);
            x=x+s(i)*conv_fft(ui,conj(vi));
        end
        x=x./DD;
        
        ratio(iter)=norm(x(:)-x_old(:))/norm(x_old(:));
    
        if trace
            fprintf('Iteration %4d, RMSE = %.10f \n',iter,ratio(iter))
        end
        
        if ratio(iter)<tol
            si=1;
            ratio=ratio(1:iter);
            break;
        elseif ratio(iter)>1
            break;
        end
        
    end
    
end