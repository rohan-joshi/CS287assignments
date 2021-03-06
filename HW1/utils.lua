VERBOSITY = 3
ERROR_TOLERANCE = 0.1

function printv(s, verbosity)
	if VERBOSITY >= verbosity then
		print(s)
	end
end

function printtest(s, result)
	if result then
		print("\x1B[32m" .. s .. " passed")
	else
		print("\x1B[31m" .. s .." failed")
	end
end

function printoptions(opt)
    print("Datafile:", opt.datafile, "Classifier:", opt.classifier, "Alpha:", opt.alpha, "Eta:", opt.eta, "Lambda:", opt.lambda, "Minibatch size:", opt.minibatch, "Num Epochs:", opt.epochs, "Minimum Sentence Length:", opt.min_sentence_length)
end

function createCountsMatrix(training_input, training_output, nfeatures, nclasses)

	local F = torch.zeros(nfeatures, nclasses)
	printv("     CreateCountsMatrix: Loaded training data", 3)
	local train_size = training_input:size()
	for n = 1, train_size[1] do
		for j = 1, train_size[2] do
			feat = training_input[n][j] - 1
			class = training_output[n]
			if feat > 0 then
				F[feat][class] = F[feat][class] + 1
			end
		end
	end
	printv("     CreateCountsMatrix: Calculated counts", 3)
	return F
end

-- returns a one-hot tensor of size n with a 1 the ith place.
--    Note that this is 1-indexed
function makeOneHot(i, n)
	local tmp_tensor = torch.zeros(n)
	tmp_tensor[i] = 1
	return tmp_tensor
end

-- convert from sparse 1-padded 1-dimensional tensor to real 1-dimensional tensor
function convertSparseToReal(sparse, numFeatures)
	local res = torch.zeros(numFeatures):double()
	for i = 1, sparse:size()[1] do
		local ind = sparse[i] - 1
		if ind > 0 then
			res[ind] = res[ind] + 1
		end
	end
	return res
end


-- A is a sparse tensor with 1-padding
-- B is a dense tensor
-- Matrix multiplication A*B in the straightforward way
function sparseMultiply(A,B)
	local numRows = A:size()[1]
	local numCols = B:size()[2]

	local output = torch.Tensor(numRows, numCols)
	for r = 1, numRows do
		-- Grab the indicies that are not padding
		local indicies = (A[r] - 1)[(A[r] - 1):ge(1)]
		if (indicies:size():size() > 0) then
			output[r] = B:index(1, indicies):sum(1)
		end
	end
	return output
end

function getLinearModelPredictions(W, b, X)
    local Ans = sparseMultiply(X, W:t())
    for r = 1, Ans:size(1) do
    	Ans[r]:add(b)
    end
    local a, c = torch.max(Ans, 2)
    return c
end    


-- W and b are the weights to be trained. X is the sparse matrix representation of the input. Y is the classes
function validateLinearModel(W, b, x, y)
    local c = getLinearModelPredictions(W, b, x)
    equality = torch.eq(c, y)

    score = equality:sum()/equality:size()[1]
    return score
end   

-- Returns another tensor with only the rows of X that have sentences of length minlength

function removeSmallSentences(X, Y, minlength)
    local desired_row_mask = torch.ge(torch.ge(X, 2):sum(2), minlength)
    local desired_rows = torch.range(1, X:size()[1]):long()[desired_row_mask]
    return X:index(1, desired_rows), Y:index(1, desired_rows)
end

--compare two tensors
function tensorsEqual(A, B)
	if ((torch.abs(A-B)):sum()) < ERROR_TOLERANCE then
		return true
	else
		local N = A:size()[1]
		for i=1, N do
			local err = 0
			if A:dim() == 2 then
				err = (torch.abs(A[i] - B[i])):sum()
			else
				err = (torch.abs(A[i] - B[i]))
			end
			if err > ERROR_TOLERANCE/N then
				print(i, "A[i]:", A[i], "B[i]", B[i], "diff:", err)
				break
			end
		end
	end
end


function split_test_train(X_vals, Y_vals, train_ratio)
    local total_size = X_vals:size()[1]
    local cutoff = total_size*train_ratio
    local train_in = X_vals:index(1, torch.range(1, cutoff):long())
    local train_out = Y_vals:index(1, torch.range(1, cutoff):long())
    local test_in = X_vals:index(1, torch.range(cutoff+1, total_size):long())
    local test_out = Y_vals:index(1, torch.range(cutoff+1, total_size):long())
    return train_in, train_out, test_in, test_out
end
