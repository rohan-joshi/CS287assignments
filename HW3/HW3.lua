-- Only requirements allowed
require("hdf5")
require("nn")
require("optim")

cmd = torch.CmdLine()

-- Cmd Args
cmd:option('-datafile', '', 'data file')
cmd:option('-testfile', '', 'test file')
cmd:option('-save_losses', '', 'file to save loss per epoch to (leave blank if not wanted)')
cmd:option('-classifier', 'nn', 'classifier to use (mle, nn)')
cmd:option('-alpha', 1, 'laplacian smoothing factor')
cmd:option('-eta', .1, 'Learning rate (.1 for adagrad, 500 for sgd, 10 for nn sgd)')
cmd:option('-lambda', 0, 'regularization penalty (not implemented)')
cmd:option('-minibatch', 2000, 'Minibatch size (500 for nn, 2000 for lr)')
cmd:option('-epochs', 20, 'Number of epochs of SGD')
cmd:option('-optimizer', 'sgd', 'Name of optimizer to use (adagrad or sgd)')
cmd:option('-hiddenlayers', 10, 'Number of hidden layers (if using neural net)')
cmd:option('-embedding_size', 50, 'Size of word embedding')
cmd:option('-odyssey', false, 'Set to true if running on odyssey')
cmd:option('-K', 10, 'for NCE only')

-- Hyperparameters
-- ...


function main() 
   -- Parse input params
   opt = cmd:parse(arg)

   --print("Datafile:", opt.datafile, "Classifier:", opt.classifier, "Alpha:", opt.alpha, "Eta:", opt.eta, "Lambda:", opt.lambda, "Minibatch size:", opt.minibatch, "Num Epochs:", opt.epochs, "Optimizer:", opt.optimizer, "Hidden Layers:", opt.hiddenlayers, "Embedding size:", opt.embedding_size)


   _G.path = opt.odyssey and '/n/home09/ankitgupta/CS287/CS287assignments/HW3/' or ''

   dofile(_G.path..'train.lua')
   dofile(_G.path..'multinomial.lua')
   dofile(_G.path..'utils.lua')

   printoptions(opt)

   local f = hdf5.open(opt.datafile, 'r')
   local f2 = hdf5.open("samples.hdf5")
   local samples = f2:read("samples"):all():long()

   local nclasses = f:read('numClasses'):all():long()[1]
   local nfeatures = f:read('numFeatures'):all():long()[1]
   local d_win = f:read('d_win'):all():long()[1]

   print("nclasses:", nclasses, "nfeatures:", nfeatures, "d_win:", d_win)

   local training_input = f:read('train_input'):all():long()   
   local training_output = f:read('train_output'):all():long()

   local valid_input = f:read('valid_context'):all():long()
   local valid_options = f:read('valid_options'):all():long()
   local valid_true_outs = f:read('valid_true_outs'):all():long()

   local test_context = f:read('test_context'):all():long()
   local test_options = f:read('test_options'):all():long()

   local result

   -- Train neural network.
   if opt.classifier == "nn" then
   		local model, criterion = neuralNetwork(nfeatures, opt.hiddenlayers, nclasses, opt.embedding_size, d_win)
   		model = trainModel(model, criterion, training_input, training_output, valid_input, valid_options, valid_true_outs, opt.minibatch, opt.epochs, opt.optimizer, opt.save_losses)
		local acc, cross_entropy_loss = getaccuracy2(model, valid_input, valid_options, valid_true_outs)
		--result = predictall_and_subset(model, valid_input, valid_options, nclasses, opt.alpha)
		--local acc = get_result_accuracy(result, valid_input, valid_options, valid_true_outs)
    	printoptions(opt)
    	print("Results:", acc, cross_entropy_loss)

    	--print(acc)

		--print("Accuracy:")
		--print(getaccuracy(model, valid_input, valid_options, valid_true_outs))
	elseif opt.classifier == 'nce' then
		local model, lookup, bias = trainNCEModel(training_input, training_output,
					valid_input, 
					valid_options,
					valid_true_outs,
					opt.minibatch, 
					opt.epochs, 
					opt.optimizer, 
					opt.save_losses,
					nfeatures, opt.hiddenlayers, nclasses, opt.embedding_size, d_win, opt.alpha, opt.eta, samples, opt.K)

    -- Combine the models to a normal nn model for making predictions
    local prediction_model = make_NCEPredict_model(model, lookup, bias, opt.hiddenlayers, nclasses)
    local acc, cross_entropy_loss = getaccuracy2(prediction_model, valid_input, valid_options, valid_true_outs)
    printoptions(opt)
    print("Results:", acc, cross_entropy_loss)


    elseif opt.classifier == 'multinomial' then
    	local reverse_trie = fit(training_input, training_output)
    	--print(get_word_counts_for_context(reverse_trie, torch.LongTensor{}, nclasses, opt.alpha))
		  local predicted_distributions = predictall_and_subset(reverse_trie, valid_input, valid_options, nclasses, opt.alpha)
    	--print(predicted_distributions:sum(2))
    	local cross_entropy_loss = cross_entropy_loss(valid_true_outs, predicted_distributions, valid_options)
    	print("Cross-entropy loss", cross_entropy_loss)

    	--result = predictall_and_subset(reverse_trie, test_context, test_options, nclasses, opt.alpha)

    	local acc = get_result_accuracy(predicted_distributions, valid_input, valid_options, valid_true_outs)
    	printoptions(opt)
    	print("Results:", acc, cross_entropy_loss)
    else
    	print("Error: classifier '", opt.classifier, "' not implemented")
    end

    if (opt.testfile ~= '') then
        --print("Writing to test file")
    	write_predictions(result, opt.testfile)
    end





end

main()
