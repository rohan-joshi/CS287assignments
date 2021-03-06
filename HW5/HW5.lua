-- Only requirements allowed
require("hdf5")
require("nn")
require("optim")

cmd = torch.CmdLine()

-- Cmd Args
cmd:option('-datafile', '', 'data file')
cmd:option('-classifier', 'hmm', 'classifier to use')
cmd:option('-alpha', 1, 'laplacian smoothing factor')
cmd:option('-beta', 1, 'F score parameter')
cmd:option('-odyssey', false, 'Set to true if running on odyssey')
cmd:option('-testfile', '', 'test file (must be HDF5)')
cmd:option('-embedding_size', 50, 'Size of embeddings')
cmd:option('-minibatch_size', 320, 'Size of minibatches')
cmd:option('-optimizer', 'sgd', 'optimizer to use')
cmd:option('-epochs', 10, 'Number of epochs')
cmd:option('-hidden', 50, 'Hidden layer (set to 0 to not have hidden layer for memm)')
cmd:option('-eta', 0.001, 'Learning rate')
cmd:option('-beam', false, 'If true then use beam search instead of viterbi')

-- Hyperparameters
-- ...


function main() 
	-- Parse input params
	opt = cmd:parse(arg)

	_G.path = opt.odyssey and '/n/home09/ankitgupta/CS287/CS287assignments/HW5/' or ''

	dofile(_G.path..'utils.lua')
	dofile(_G.path..'hmm.lua')
	dofile(_G.path..'memm.lua')
	dofile(_G.path..'structuredperceptron.lua')
	printoptions(opt)

	local f = hdf5.open(opt.datafile, 'r')

	local nclasses = f:read('numClasses'):all():long()[1]
	local nsparsefeatures = f:read('numSparseFeatures'):all():long()[1]
	local ndensefeatures = f:read('numDenseFeatures'):all():long()[1]
	local start_class = f:read('startClass'):all():long()[1]
	local end_class = f:read('endClass'):all():long()[1]
	--local dwin = f:read('dwin'):all():long()[1]

	local o_class = 1

	print("nclasses:", nclasses, "nsparsefeatures:", nsparsefeatures, "ndensefeatures:", ndensefeatures)

	local sparse_training_input = f:read('train_sparse_input'):all():long()
	local dense_training_input = f:read('train_dense_input'):all():double()
	local training_output = f:read('train_output'):all():long()

	local sparse_validation_input = f:read('valid_sparse_input'):all():long()
	local dense_validation_input = f:read('valid_dense_input'):all():double()
	
	local validation_output = f:read('valid_output'):all():long()
	local word_embeddings = f:read('word_embeddings'):all():double() 

	local sparse_test_input = f:read('test_sparse_input'):all():long()
	local dense_test_input = f:read('test_dense_input'):all():double()

	ssv, dsv, osv = split_data_into_sentences(sparse_validation_input, dense_validation_input, validation_output, end_class)

	if (opt.beam) then
		viterbi_alg = wrap_beam_search(50)
	else
		viterbi_alg = viterbi
	end

	if opt.classifier == "hmm" then
		predictor = hmm_train(sparse_training_input:squeeze(), training_output, nsparsefeatures, nclasses, opt.alpha)

		includeDense = false

	elseif (opt.classifier == 'memm') then

		local model = train_memm(sparse_training_input, dense_training_input, training_output, 
						nsparsefeatures, ndensefeatures, nclasses, opt.embedding_size, opt.epochs, opt.minibatch_size, opt.eta, opt.optimizer, opt.hidden)

		predictor = make_predictor_function_memm(model, nsparsefeatures)

		includeDense = true

	elseif (opt.classifier == 'struct') then
		-- sst = {}
		-- dst = {}
		-- ost = {}
		-- sst[1] = sparse_training_input
		-- dst[1] = dense_training_input
		-- ost[1] = training_output
		local sst, dst, ost = split_data_into_sentences(sparse_training_input, dense_training_input, training_output, end_class)
		model, predictor = train_structured_perceptron(viterbi_alg, sst, dst, ost, opt.epochs, nclasses, start_class, end_class, nsparsefeatures, ndensefeatures, opt.embedding_size, opt.eta, opt.hidden)

		includeDense = true

	else
		print("error: ", opt.classifier, " is not implemented!")
	end

	print("NEW METHOD: Returning Viterbi Predictions for each sentence separately in validation set")
	local valid_predicted_output = predict_each_sentence(viterbi_alg, ssv, dsv, nclasses, predictor, start_class, includeDense)


	-- print("Starting Viterbi on validation set...")
	-- if include_dense_feats then
	-- 	valid_predicted_output = viterbi(sparse_validation_input, predictor, nclasses, start_class, dense_validation_input)
	-- else
	-- 	valid_predicted_output = viterbi(sparse_validation_input:squeeze(), predictor, nclasses, start_class)
	-- end

	print("Done. Converting to Kaggle-ish format...")
	local ms, mc, s = find_kaggle_dims(osv, o_class)
	local ms2, mc2, s2 = find_kaggle_dims(valid_predicted_output, o_class)
	ms = math.max(ms, ms2)
	mc = math.max(mc, mc2)
	if (s ~= s2) then
		for i=1, validation_output:size(1) do
			if (validation_output[i] == 9 and valid_predicted_output[i] ~= 9) or (validation_output[i] ~= 9 and valid_predicted_output[i] == 9) then
				print(validation_output[i], valid_predicted_output[i])
			end
		end
		print(s, s2)
	end
	assert(s == s2)
	local valid_true_kaggle = kagglify_output(osv, o_class, ms, mc, s)
	local valid_pred_kaggle = kagglify_output(valid_predicted_output, o_class, ms, mc, s)


	print("Done. Computing statistics...")
	local f_score = compute_f_score(opt.beta, valid_true_kaggle, valid_pred_kaggle)
	printoptions(opt)
	print("F-Score:", f_score)

	if (opt.testfile ~= '') then
		print("Starting Viterbi on test set (sentence by sentence)...")
		test_predicted_output = predict_each_sentence(viterbi_alg, ssv, dsv, nclasses, predictor, start_class, includeDense)

		-- Make sure that the start and end sentence tags are correctly predicted.
		-- for i = 1, test_predicted_output:size(1) do
		-- 	if test_predicted_output[i] == 9 and sparse_test_input[i][2] ~= 3 then
		-- 		print(i, test_predicted_output[i], sparse_test_input[i][2])
		-- 		assert(false)
		-- 	end
		-- 	if test_predicted_output[i] == 8 and sparse_test_input[i][2] ~= 2 then
		-- 		print(i, test_predicted_output[i], sparse_test_input[i][2])
		-- 		assert(false)
		-- 	end
		-- end
		-- print(test_predicted_output:size(1), sparse_test_input:size(1))

		print("Done. Converting to Kaggle-ish format...")
		local tms, tmc, ts = find_kaggle_dims(test_predicted_output, o_class)
		local test_pred_kaggle = kagglify_output(test_predicted_output, o_class, tms, tmc, ts)
	
		-- local tms, tmc, ts = find_kaggle_dims(validation_output, start_class, end_class, o_class)
		-- local test_pred_kaggle, _, _, _ = kagglify_output(validation_output, start_class, end_class, o_class, tms, tmc, ts)
		print("Done. Writing test out to HDF5...")
		local f = hdf5.open(opt.testfile, 'w')
		f:write('test_outputs', test_pred_kaggle:long())

		local ftest = hdf5.open('VALIDTEST.hdf5', 'w')
		ftest:write('test_outputs', valid_true_kaggle:long())

		print("Done. Wrote to ", opt.testfile, ".")
		print("\x1B[32m".."To finish this process, now run `python write_to_kaggle.py "..opt.testfile.."`".."\x1b[0m")

	end


end

main()
