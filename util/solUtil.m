classdef solUtil

    methods(Static)
        
        function [nneg,lor,rlor,psd] = GetDualSlacks(y,A,c,K)
            
            offset = K.f;
            indx = 1:K.f;
            freeDual = c(indx)' - y'*A(:,indx);

            indx = offset+[1:K.l];
            nneg = c(indx)' - y'*A(:,indx);
            offset = offset + K.l;

            for i=1:length(K.q)
                indx = offset + [1:K.q(i)];
                lor{i} = c(indx)' - y'*A(:,indx);
                offset = offset + K.q(i);
            end

            for i=1:length(K.r) 
                indx = offset + [1:K.r(i)];
                rlor{i} = c(indx)' - y'*A(:,indx);
                offset = offset + K.r(i);
            end

            for i=1:length(K.s)
                indx = offset + [1:K.s(i).^2];
                psd{i} = mat(c(indx)' - y'*A(:,indx));
                offset = offset + K.s(i).^2;
            end
            
        end
        
        function [nneg,lor,rlor,psd]  = GetPrimalVars(x,K)

            offset = K.f;

            indx = offset+[1:K.l];
            nneg = x(indx);
            offset = offset + K.l;

            for i=1:length(K.q)
                indx = offset + [1:K.q(i)];
                lor{i} = x(indx);
                offset = offset + K.q(i);
            end

            for i=1:length(K.r) 
                indx = offset + [1:K.r(i)];
                rlor{i} = x(indx);
                offset = offset + K.r(i);
            end
            
            for i=1:length(K.s)
                indx = offset + [1:K.s(i).^2];
                psd{i} = mat(x(indx));
                offset = offset + K.s(i).^2;
            end
            
        end
    
        function success = CheckPrimal(x,A,b,c,K,eps)

            if ~exist('eps','var') || isempty(eps)
                eps = 10^-8;
            end

            [l,q,r,s] = solUtil.GetPrimalVars(x,K);
            pass = [];

            pass(end+1) = all(l >= 0);

            for i=1:length(q) 
                pass(end+1) = solUtil.CheckLor( q{i},eps);
            end

            for i=1:length(s)
                pass(end+1) = solUtil.CheckPSD( s{i},eps);
            end

            pass(end+1) = norm(A*x-b) < eps;
            success = all(pass==1);
       
        end


        function success = CheckDual(y,A,b,c,K,eps)

            if ~exist('eps','var') || isempty(eps)
                eps = 10^-8;
            end
            
            [l,q,r,s] = solUtil.GetDualSlacks(y,A,c(:),K);
            pass = [];
            for i=1:length(q) 
                pass(end+1) = solUtil.CheckLor( q{i},eps);
            end

            for i=1:length(s)
                pass(end+1) = solUtil.CheckPSD( s{i},eps);
            end
            success = all(pass == 1);

        end
        
         
        function [dimOut] = GetSubSpaceDim(self,Primal)

            A = self.A; 
            b = self.b;
            c = self.c;
            K = self.K;
            cone = coneBase(K);
            useQR = 1;
            A = CleanLinear(A,b,useQR);
            numIndEq = size(A,1);
            dimP = cone.NumVar - numIndEq;

            A = CleanLinear(self.A,self.b*0,useQR); 
            numIndGen = size(A,1);

            dualEqs = CleanLinear(self.A(:,1:K.f)',self.c(1:K.f)',useQR); 
            numIndDualEq = size(dualEqs,1);
            dimD = numIndGen - numIndDualEq;

            if (dimP + dimD ~= cone.NumVar-numIndDualEq)
                error('dim calc error')       
            end

            if Primal
                dimOut = dimP;
            else
                dimOut = dimD;
            end

        end
                 
        function pass = CheckLor(x,eps)
            pass = 1;
            if length(x) > 0
                if x(1) - norm(x(2:end)) > -eps
                    pass = 1;
                else
                    pass = 0;
                end
            end
        end

        function pass = CheckPSD(x,eps)
            if issparse(x)
               eigf = @eigs;
            else
               eigf = @eig; 
            end
            if (min(eigf(x)) > -eps) 
                pass = 1;
            else
                pass = isempty(x);
            end
        end
        
        
        function pass = CheckInFace(x,U,K,eps)
            
            x = full(x);
            cone = coneBase(K);
             Kf = K;
            if (~isempty(U))
                Tuu = cone.BuildMultMap(U,U);
                xface = Tuu*x(:);
                Kf.s = cellfun(@(x) size(x,2), U);
            else
                xface = x(:);
            end
                 
            face = coneBase(Kf);
            
            for i=1:length(Kf.s)
                [s,e] = face.GetIndx('s',i);

                xtest = mat(xface(s:e));

                if (min(eig(xtest)) > -eps) 
                    pass(i) = 1;
                else
                    pass(i) = isempty(xtest);
                end
            
            end
            
            pass = all(pass);
            
        end
        
                                          
        function [xr,success,deltas] = LineSearch(x,U,redCerts,Korig,ComputeDelta)
            fail = [];

            for i=length(U):-1:1

                fail(i) = 1;
                if (i >= 2)

                    Uface = U{i-1};

                else

                    Uface = [];

                end

               delta = 0.0;
                
               for k = 1:100
                    deltas(i) = delta;
                    deltaX = ComputeDelta(delta,redCerts{i});
                    xr = x(:)+deltaX(:);
                    feas = solUtil.CheckInFace(xr,Uface,Korig,eps);
                    if (feas == 0)
                        delta = delta+1;
                    else
                        x = xr;
                        
                        fail(i) =  0;
                        break;
                    end
               end

            end
            
            success = ~any(fail == 0);
            
        end
        
        
                
        
        
        function U = ExpandU(U)
            for i=2:length(U) 
                for j=1:length(U{i});
                U{i}{j} = U{i-1}{j}*U{i}{j};
                end
            end
        end
        
    end
            
end
