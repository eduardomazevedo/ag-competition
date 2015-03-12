classdef healthcaralognormalmodel_nl < model
    %   healthcaralognormalmodel_nl Creates a health insurance model as in
    %   the Azevedo and Gottlieb paper. Subclass of the model class.
    %   This model has CARA preferences, normal losses, lognormally
    %   distributed types, and contracts are parametrized by three elements
    %   as in Einav et al. (2013). Inputs to the constructor:
    %   deductibleVector is a vector of deductibles, coinsuranceVector is a vector
    %   of coinsurance shares, oopVector is a vector with out of pocket maximum
    %   values, parameterMean is a 4 dimensional vector of means of parameters
    %   and parameterLogVariance is a 4x4 matrix of log covariances.
    %   Parameters are ordered as A, H, M, S as in the Azevedo and Gottlieb
    %   paper (absolute risk aversion A, moral hazard H, mean loss M,
    %   and standard deviation of losses S).
    
    properties
        publicInsuranceMaximum
        nullContract
        typeDistributionMean
        typeDistributionLogCovariance
    end
    
    methods
        % Constructor
        function obj = healthcaralognormalmodel_nl(deductibleVector, ...
                coinsuranceVector, oopMaxVector, publicInsuranceMaximum, ...
                typeDistributionMean, typeDistributionLogCovariance)
            
            obj.typeDistributionMean = typeDistributionMean;
            obj.typeDistributionLogCovariance = typeDistributionLogCovariance;
            n = length(deductibleVector);
            for i = 1:n
                x.deductible       = deductibleVector(i) ;
                x.coinsurance      = coinsuranceVector(i) ;
                x.oopMax           = oopMaxVector(i) ;
                x.name             = num2str(i);
                obj.contracts{i} = x;
            end;
            
            obj.publicInsuranceMaximum   = publicInsuranceMaximum;
            obj.nullContract.deductible  = publicInsuranceMaximum;
            obj.nullContract.coinsurance = 1;
            obj.nullContract.oopMax      = publicInsuranceMaximum;
            obj.nullContract.name        = 'Null Contract';
        end
        
        function u = uFunction(obj, x, type)
            
            % Checking contract
            checkContract(obj, x);
            
            % If contract is null, then return zero
            if (x.deductible == obj.publicInsuranceMaximum)
                u = 0;
                return
            end
            
            % Calculate ex post utility in case of no losses
            [uEx_0, ~, ~, bounds] = exPostUtility(obj, x, type, 0);
            % Calculate limit of integration for the expectation
            limits = integrationLimits(obj, type, 1e-2);
            u0 = 0; % Willingness to pay with no insurance
            u = 0; % With insurance
            
            if (type.A > 0)
                
                [~, K] = fminbnd( @(l) - log( lossDistributionFunction(obj, type, l))...
                    + type.A * exPostUtility(obj, x, type, l), 0, limits(2) - 1 );
                K = -K;
                
                [~, K0] = fminbnd( @(l) - log( lossDistributionFunction(obj, type, l))...
                    + type.A * exPostUtility(obj, obj.nullContract, type, l), 0, limits(2) - 1 );
                K0 = -K0;
                
                if (limits(1) < 0) % Integrals in the region of no loss
                    
                    % Calculate the probability of the loss being zero
                    
                    p_0 = integral(@(l) lossDistributionFunction(obj, type, l), ...
                        limits(1), min(limits(2),0), 'AbsTol', 1e-15,'RelTol',1e-12 );
                    
                    u = p_0 * exp(-type.A * uEx_0 - K);
                    
                    % In case of no insurance, ex post utility is zero
                    
                    u0 = p_0 * exp(-K0);
                    
                end
                
                if (limits(2) > 0)
                    
                    u = u + integral(@(l) exp(-type.A*exPostUtility(obj, x, type, l) + ...
                        log(lossDistributionFunction(obj, type, l)) - K), ...
                        max(limits(1),0), limits(2),...
                        'AbsTol', 1e-15,'RelTol',1e-12,'WayPoints',bounds(isfinite(bounds)));
                    
                    u0 = u0 + integral(@(l) exp(-type.A * ...
                        exPostUtility(obj, obj.nullContract, type, l) +...
                        log(lossDistributionFunction(obj, type, l)) - K0), ...
                        max(limits(1),0), limits(2),...
                        'AbsTol', 1e-15,'RelTol',1e-12,'WayPoints',bounds(isfinite(bounds)));
                    
                end
                
                u = -( log(u) + K )/type.A;
                u0 = -( log(u0) + K0 )/type.A;
                
            else % In the case of risk neutrality
                
                if (limits(1) < 0)
                    
                    p_0 = integral(@(l) lossDistributionFunction(obj, type, l), ...
                        limits(1), min(limits(2),0), 'AbsTol', 1e-15,'RelTol',1e-12 );
                    
                    u = p_0 * uEx_0;
                    
                    u0 = p_0;
                    
                end
                
                if (limits(2) > 0)
                    
                    u = u + integral(@(l) exPostUtility(obj, x, type, l) .*...
                        lossDistributionFunction(obj, type, l), max(limits(1),0), limits(2),...
                        'AbsTol', 1e-15,'RelTol',1e-12,'WayPoints',bounds(isfinite(bounds)));
                    
                    u0 = u0 + integral(@(l) exPostUtility(obj, obj.nullContract, type, l) .*...
                        lossDistributionFunction(obj, type, l), max(limits(1),0), limits(2),...
                        'AbsTol', 1e-15,'RelTol',1e-12,'WayPoints',bounds(isfinite(bounds)));
                    
                end
            end
            
            if ( (u0 - u)/abs(u) > 1e-6 )
                fprintf('Utility with insurance: %.8f\n',u)
                fprintf('Utility without insurance: %.8f\n',u0)
                error('Utility without insurance cannot be higher than with it')
            end
            
            u  = u - u0;
            
            if ( u > obj.publicInsuranceMaximum + type.H / 2 )
                u = obj.publicInsuranceMaximum + type.H / 2;
                warning('Impossible value, setting u = publicInsuranceMaximum + type.H / 2')
            end
            
        end
        
        function c = cFunction(obj, x, type)
            
            % Checking contract
            checkContract(obj, x);
            
            % If contract is null, then return zero cost
            
            if (x.deductible == obj.publicInsuranceMaximum)
                c = 0;
                return
            end
            
            [c0, bounds] = exPostCost(obj, x, type, 0);
            limits = integrationLimits(obj, type, 1e-2);
            c = 0;
            
            if (limits(1) < 0)
                
                c = integral(@(l) lossDistributionFunction(obj,type,l), ...
                    limits(1),max(0,limits(2)),...
                    'AbsTol', 1e-15,'RelTol',1e-12)*c0;
                
            end
            
            if (limits(2) > 0)
                
                c = c + integral(@(l) exPostCost(obj, x, type, l).*...
                    lossDistributionFunction(obj, type, l),max(0,limits(1)),limits(2),...
                    'AbsTol', 1e-15,'RelTol',1e-12,'WayPoints',bounds(isfinite(bounds)));
                
            end
            
        end
        
        function Type = typeDistribution(obj)
            
            v = lognrndfrommoments(...
                obj.typeDistributionMean, obj.typeDistributionLogCovariance, 1);
            
            Type.A = v(1);
            Type.H = v(2);
            Type.MReal = v(3);
            Type.SReal = v(4);
            
            Psi = @(x) normcdf(0,x(1),x(2));
            psi = @(x) normpdf(0,x(1),x(2));
            mills = @(x) psi(x)/(1-Psi(x));
            alpha = @(x) -x(1)/x(2);
            
            system = @(x) [ (1-Psi(x))*x(1) + x(2)*psi(x) - Type.MReal , ...
                x(2)^2 * (1-Psi(x)) *( 1 - mills(x)^2 + mills(x)*alpha(x) ...
                + (alpha(x) - mills(x))^2 * Psi(x) ) - Type.SReal^2 ];
            
            options = optimset('MaxFunEvals',1000);
            [x y] = simulannealbnd(@(x) sum(abs(system(x))),[Type.MReal Type.SReal],[0,Type.SReal],[Type.MReal Inf])
            
            Type.M = x(1);
            Type.S = x(2);
            
            function v = ...
                    lognrndfrommoments(meanVector, logCovMatrix, varargin)
                %   estimate_lognormal_from_moments Estimate lognormal parameters
                %   Inputs: a line vector of means, and a log covariance matrix.
                %   Outputs: A line vector of draws. Optional argument for number of lines.
                %   Warning: for some reason MATLAB chokes if one of the variables has 0
                %   variance, so always put at least a tiny bit of bogus variance.
                
                nDraws = 1;
                if (length(varargin) == 1)
                    nDraws = varargin{1};
                end;
                
                % Find lognormal parameters
                sigmaMatrix = cholcov(logCovMatrix);
                b  = sum(sigmaMatrix.^2, 1);
                mu = log(meanVector) - b/2;
                
                % Draw
                x = randn(nDraws, length(meanVector));
                v = exp(repmat(mu,[nDraws, 1]) + x * sigmaMatrix);
            end
            
        end
        
        function checkContract(obj, x)
            if ( x.coinsurance < 0 || x.coinsurance > 1 )
                error('Coinsurance must be between zero and one')
            elseif ( x.deductible > x.oopMax || x.deductible < 0 )
                error(['Deductible must be higher than zero, and lower than'...
                    ' the out of pocket maximum'])
            elseif ( x.oopMax > obj.publicInsuranceMaximum )
                error(['Out of pocket maximum must be lower than the public'...
                    'insurance maximum'])
            end
        end
        
        function limits = integrationLimits(obj, type, tol)
            % Finds the smallest possible interval such that all points in
            % it have positive (at machine accuracy) density. Perfoms a
            % check to see if integrating the density between these points
            % results in 1
            
            limits(1) = findCloserZero(type.M,1e6,tol);
            limits(2) = findCloserZero(type.M,-1e6,tol);
            
            integralCheck = integral(@(l)...
                lossDistributionFunction(obj, type, l), ...
                limits(1),limits(2),'AbsTol', 1e-15,'RelTol',1e-12);
            
            if ( abs(integralCheck - 1) > 1e-6 )
                error('Integral could not be well approximated, or this is not a distribution')
            end
            
            function b = findCloserZero(b,d_init,tol)
                f_b = 0;
                d = d_init;
                while (abs(d) > tol || f_b > 0)
                    b = b - d;
                    f_b = obj.lossDistributionFunction(type,b);
                    if (f_b == 0)
                        if (sign(d) == sign(d_init))
                            d = - d / 10;
                        end
                    else
                        if (sign(d) ~= sign(d_init))
                            d = -d / 10;
                        end
                    end
                end
            end
            
        end
        
        function x = lossDistributionFunction(~,type,l)
            x = normpdf(l,type.M,type.S);
        end
        
        function [cost, bounds] = exPostCost(obj, x, type, losses)
            if (x.deductible == obj.publicInsuranceMaximum)
                cost = 0;
                bounds = 0;
            else
                [~, expenditure, copay, bounds] = exPostUtility(obj, x, type, losses);
                cost = expenditure - copay;
            end
        end
        
        function [u, expenditure, payment, bounds] = exPostUtility(obj, x, type, losses)
            
            % Initializing variables
            u = zeros(1, length(losses));
            expenditure = zeros(1, length(losses));
            payment = zeros(1, length(losses));
            bounds = zeros(length(losses), 3);
            
            for i = 1:length(losses)
                
                % Loss is bounded below by zero
                l = max(losses(i), 0);
                
                % Calculating the loss boundaries for each interval of expenses
                bounds(i, 1) = max(min(x.deductible-(1-x.coinsurance)*type.H/2,x.oopMax-type.H/2),0);
                bounds(i, 2) = max(x.deductible-(1-x.coinsurance)*type.H/2,0);
                bounds(i, 3) = max((x.oopMax-(1-x.coinsurance)*x.deductible)/x.coinsurance ...
                    - (2 - x.coinsurance) * type.H / 2, 0);
                
                if (x.deductible == obj.publicInsuranceMaximum)
                    u(i) = max(-l,-obj.publicInsuranceMaximum);
                    payment(i) = min(l,obj.publicInsuranceMaximum);
                    expenditure(i) = l;
                elseif l < bounds(i, 1)
                    expenditure(i) = l;
                    u(i) = -l;
                    payment(i) = l;
                elseif (l >= bounds(i, 2)) && (l <= bounds(i, 3))
                    u(i) = (1-x.coinsurance)^2*type.H/2 - (1-x.coinsurance)*x.deductible - x.coinsurance*l;
                    expenditure(i) = (1-x.coinsurance)*type.H + l;
                    payment(i) = x.deductible + (1-x.coinsurance)*(expenditure(i)-x.deductible);
                    
                else
                    u(i) = type.H/2 - x.oopMax;
                    expenditure(i) = type.H + l;
                    payment(i) = x.oopMax;
                end
            end
        end
        
        function [populationSize, CalculationParametersEquilibrium, CalculationParametersOptimum] = ...
                suggestComputationParameters(Model, percentError)
            
            nContracts = Model.nContracts;
            Population = population(Model, 100);
            priceOrderOfMagnitude = mean(Population.cMatrix(:));
            
            populationSize = ...
                floor(nContracts / percentError^2 / 2);
            CalculationParametersEquilibrium.behavioralAgents = ...
                percentError;
            CalculationParametersEquilibrium.fudge = ...
                percentError / nContracts / 100;
            CalculationParametersEquilibrium.tolerance = ...
                percentError * priceOrderOfMagnitude;
            CalculationParametersEquilibrium.maxIterations = ...
                floor(10 / CalculationParametersEquilibrium.fudge);
            
            CalculationParametersOptimum.tolerance = CalculationParametersEquilibrium.tolerance;
            CalculationParametersOptimum.maxIterations = 10^4;
        end;
        
    end
end

