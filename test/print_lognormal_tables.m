%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% print_lognormal_tables.m %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%{
Author: Eduardo Azevedo and Rafael Mourao
Date:   2015-03-20

Simple script to print test tables from variables. Create matlab tables and
print to an text files

%}

addpath('../classes')
load('tests.mat')
format shortg

file = @(x) ['test_lognormal_' num2str(x) '.txt'];
Testnames = {'High Aversion, Low MH Variance', 'Medium Aversion, Low MH Variance',...
    'Low Aversion, Low MH Variance', 'High Aversion, High MH Variance',...
    'Medium Aversion, High MH Variance', 'Low Aversion, High MH Variance'};

for i = 1:length(test)
   
ncontracts = test(i).Population(1).nContracts;
nPopulations = length(test(i).Population) / 2; % Number of population objects is doubled to consider the mandate case
contractinfo = {'Deductible','Coinsurance','OOP Max','Mean Coverage'}';
for j = 1:ncontracts
    contractinfo{1,j+1} = test(i).Model(1).contracts{j}.deductible;
    contractinfo{2,j+1} = test(i).Model(1).contracts{j}.coinsurance; 
    contractinfo{3,j+1} = test(i).Model(1).contracts{j}.oopMax;
    contractinfo{4,j+1} = round( test(i).Model(j).meanCoverage(test(i).Model(1).contracts{j}), 2);
end

fid = fopen(file(i),'w+');
string = evalc('disp(contractinfo)');
fwrite(fid,string);

x = cell(8,ncontracts);
Tables = cell(1,ncontracts);
 
for j = 1:nPopulations
    x(1,:)=num2cell(round(test(i).DEquilibrium{j},2));
    x(2,:)=num2cell(test(i).pEquilibrium{j});
    x(3,1)=num2cell(test(i).WEquilibrium{j});
    x(4,:)=num2cell(round(test(i).DEfficient{j},2));
    x(5,:)=num2cell(test(i).pEfficient{j});
    x(6,1)=num2cell(test(i).WEfficient{j});
    x(7,2:end)=num2cell(round(test(i).DEquilibrium{j+nPopulations},2));
    x(8,2:end)=num2cell(test(i).pEquilibrium{j+nPopulations});
    
    rowtitles = {'Equilibrium Demand','Equilibrium Prices',...
          'Equilibrium Welfare', 'Efficient Demand','Efficient Prices',...
          'Efficient Welfare','Mandate Demand','Mandate Prices'}';
      
    string = evalc('disp([rowtitles,x])'); 
    
    fprintf(fid,['\n' Testnames{j} '\n\n']);
    fwrite(fid,string);
end

fclose(fid);

end

