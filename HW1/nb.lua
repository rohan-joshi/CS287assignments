-- Only requirement allowed
require("hdf5")

cmd = torch.CmdLine()

-- Cmd Args
cmd:option('-datafile', '', 'data file')
cmd:option('-classifier', 'nb', 'classifier to use')

-- Hyperparameters
-- ...
function unitTest()
	local x = torch.ones(3, 2)
	x[1][1] = 5
	x[2][1] = 3
	x[2][2] = 2
	x[3][1] = 2
	local Wt = torch.Tensor(4, 2)
	local b = torch.ones(1, 2)
	i=0; Wt:apply(function() i = i+1; return i end)
	Wt[4][2] = 0
	local output = validateModel(Wt:t(), b, x)
	print(output)

end

function sparseMultiply(A, B)
	-- A is a sparse tensor with 1-padding
	-- B is a dense tensor
	-- Matrix multiplication A*B in the straightforward way
	numRows = A:size(1)
	numCols = B:size(2)
	local output = torch.Tensor(numRows, numCols)
	for r = 1, numRows do
		for c = 1, numCols do
			local dotProd = 0
			-- dot product of row r in dense A and col c in B
			for j = 1, A:size(2) do		
				indexIntoB = A[r][j]-1
				if indexIntoB == 0 then
					break
				else
					dotProd = dotProd + B[indexIntoB][c]
				end
			end
			output[r][c] = dotProd
		end
	end
	return output
end



function validateModel(W, b, x)
    Ans = sparseMultiply(x, W:t())
    for r = 1, Ans:size(1) do
    	Ans[r]:add(b)
    end
    a, b = torch.max(Ans, 2)
    return b
end   
    

function naiveBayes(train_data_name)
	local f = hdf5.open(opt.datafile, 'r')
	F = torch.zeros(nfeatures, nclasses)
	training_input = f:read('train_input'):all():double()
	training_output = f:read('train_output'):all():double()
	train_size = training_input:size()
	for n = 1, train_size[1] do
		for j = 1, train_size[2] do
			feat = training_input[n][j] - 1
			class = training_output[n]
			if feat > 0 then
				F[feat][class] = F[feat][class] + 1
			end
		end
	end

	-- Add a small offset to deal with divide by 0 issues
	alpha = 1
	F = F + alpha

	-- Now, we row normalize the Tensor
	sum_of_each_col = torch.sum(F, 1)
	--reciprocal = torch.cdiv(torch.ones(nclasses), sum_of_each_col)
	--print(reciprocal:size())
	p_x_given_y = torch.Tensor(nfeatures, nclasses):zero()
	for s = 1, F:size()[1] do
		p_x_given_y[s] = torch.cdiv(F[s] , sum_of_each_col)
	end
	--print(train_size[1])

	class_distribution = torch.zeros(nclasses)
	for n=1, training_output:size()[1] do
		class = training_output[n]
		class_distribution[class] = class_distribution[class] + 1
	end
	print(class_distribution, "\n")
	--print(torch.sum(class_distribution, 1))
	p_y = torch.div(class_distribution, torch.sum(class_distribution, 1)[1])
	print(p_y, "\n")










	--for n = 1, train_size[1], 1000 do
	--	print(normalized[n])
	--end
	--print(F)
	--print(sum_of_each_row)
	--print("Training input size", training_input:size(), "\n")
	--print("Training output size", training_output:size(), "\n")
	-- initialize count matrix: numFeatures x numClasses
	
end


function main() 
   -- Parse input params
   opt = cmd:parse(arg)
   local f = hdf5.open(opt.datafile, 'r')
   nclasses = f:read('nclasses'):all():long()[1]
   nfeatures = f:read('nfeatures'):all():long()[1]

   local W = torch.randn(nclasses, nfeatures)
   local b = torch.DoubleTensor(nclasses)
   local validation_input = f:read('valid_input'):all():double()
   --print(validateModel(W, b, validation_input))
   naiveBayes()
   --unitTest()
   -- Train.

   -- Test.
end

main()