-- Only requirement allowed
require("hdf5")

cmd = torch.CmdLine()

-- Cmd Args
cmd:option('-datafile', '', 'data file')
cmd:option('-classifier', 'laplace', 'classifier to use')
cmd:option('-window_size', 5, 'Window size (does not apply to rnn)')
cmd:option('-b', 50, 'Total number of sequences to split into (minibatch_size for nn)')
cmd:option('-alpha', 1, 'laplacian smoothing factor')
cmd:option('-odyssey', false, 'Set to true if running on odyssey')
cmd:option('-sequence_length', 100, 'Length of sequence in batch (for rnn only)')
cmd:option('-embedding_size', 50, 'Size of embeddings')
cmd:option('-optimizer', 'sgd', 'optimizer to use')
cmd:option('-epochs', 10, 'Number of epochs')
cmd:option('-hidden', 50, 'Hidden layer (for nn only)')
cmd:option('-eta', 1, 'Learning rate (for nn and rnn)')
cmd:option('-hacks_wanted', false, 'Enable the hacks')
cmd:option('-rnn_unit1', 'lstm', 'Determine which recurrent unit to use (lstm or gru) for 1st layer - for classifier=rnn only')
cmd:option('-rnn_unit2', 'none', 'Determine which recurrent unit to use (none lstm or gru) for 2nd layer - for classifier=rnn only')
cmd:option('-dropout', .5, 'Dropout probability, only for classifier=rnn, and if rnn_unit2 is not none')
cmd:option('-testfile', '', 'test file')
-- Hyperparameters
-- ...


function main() 
   -- Parse input params
   opt = cmd:parse(arg)

	_G.path = opt.odyssey and '/n/home09/ankitgupta/CS287/CS287assignments/HW4/' or ''

	dofile(_G.path..'multinomial.lua')
	dofile(_G.path..'utils.lua')
   dofile(_G.path..'neural.lua')



	local f = hdf5.open(opt.datafile, 'r')
	nclasses = f:read('nclasses'):all():long()[1]
	nfeatures = f:read('nfeatures'):all():long()[1]
	space_idx = f:read('spaceIdx'):all():long()[1]
   padding_idx = f:read('paddingIdx'):all():long()[1]

	-- Count based laplace
	flat_train_input = f:read('train_input'):all():long()
	flat_train_output = f:read('train_output'):all():long()
	flat_valid_input = f:read('valid_input'):all():long()
	flat_valid_output = f:read('valid_output'):all():long()
   local valid_kaggle_input = f:read('valid_kaggle_input'):all():long()
   local valid_kaggle_output = f:read('valid_kaggle_output'):all():long()
   local test_input = f:read('test_input'):all():long()	

   printoptions(opt)
   print(flat_train_input:size())
   print(flat_train_output:size())
   print(flat_valid_output:size())
   --print(flat_valid_output:narrow(1, 1, 20))
   if opt.classifier == 'laplace' then
   	local training_input, training_output = unroll_inputs(flat_train_input, flat_train_output, opt.window_size)
      --print(training_output)
   	local reverse_trie = fit(training_input, training_output)
      print(table_to_tensor(predict_laplace(reverse_trie, torch.LongTensor{space_idx}, 2, opt.alpha), 2))
      print("Got here")
   	
   	local predictions = laplace_viterbi_segment(flat_valid_input, reverse_trie, opt.alpha, opt.window_size, space_idx)
   	local accuracy = prediction_accuracy(predictions, flat_valid_output)
   	local precision = prediction_precision(predictions, flat_valid_output)
    local precision2 = prediction_precision2(predictions, flat_valid_output)
    local log_probs = laplace_log_probs(flat_valid_input, reverse_trie, opt.alpha, opt.window_size)
    local perp = perplexity(log_probs, flat_valid_output)

    print("Results:", accuracy, precision, precision2, perp)
   elseif opt.classifier == 'wb' then
   	local training_input, training_output = unroll_inputs(flat_train_input, flat_train_output, opt.window_size)
      --print(training_output)
   	local reverse_trie = fit(training_input, training_output)
   	local predictions = wb_greedily_segment(flat_valid_input, reverse_trie, opt.alpha, opt.window_size, space_idx)
   	local accuracy = prediction_accuracy(predictions, flat_valid_output)
   	local precision = prediction_precision(predictions, flat_valid_output)
    local precision2 = prediction_precision2(predictions, flat_valid_output)
    local log_probs = wb_log_probs(flat_valid_input, reverse_trie, opt.alpha, opt.window_size)
    local perp = perplexity(log_probs, flat_valid_output)

    print("Results:", accuracy, precision, precision2, perp)


   elseif opt.classifier == 'neural' then
      local model, crit = nn_model(nfeatures, opt.embedding_size, opt.window_size, opt.hidden, 2)
      local training_input, training_output = unroll_inputs(flat_train_input, flat_train_output, opt.window_size)
      trainNN(model, crit, training_input, training_output, opt.b, opt.epochs, opt.optimizer, opt.b, opt.eta)
      local predictions = nn_greedily_segment(flat_valid_input, model, opt.window_size, space_idx)
      local accuracy = prediction_accuracy(predictions, flat_valid_output)
      local precision = prediction_precision(predictions, flat_valid_output)
      local precision2 = prediction_precision2(predictions, flat_valid_output)
      local valid_input, valid_output = unroll_inputs(flat_valid_input, flat_valid_output, opt.window_size)

	local log_probs = nn_log_probs(valid_input, model, opt.window_size)
      local perp = perplexity(log_probs, valid_output)
      print("Results from greedy:", accuracy, precision, precision2, perp)
      if (opt.window_size == 1) then 
	      local predictions = nn_viterbi_segment(flat_valid_input, model, opt.window_size, space_idx)
	      local accuracy = prediction_accuracy(predictions, flat_valid_output)
	      local precision = prediction_precision(predictions, flat_valid_output)
	      local precision2 = prediction_precision2(predictions, flat_valid_output)      
	      print("Viterbi Results:", accuracy, precision, precision2, perp)
      end
      printoptions(opt)

   elseif opt.classifier == 'rnn' then
      print("RNN")
      local model, crit, embedding = rnn(nfeatures, opt.embedding_size, 2, opt.rnn_unit1, opt.rnn_unit2, opt.dropout)
      model:remember("both")
      model:training()
      local training_input, training_output = create_rnn_inputs(flat_train_input, flat_train_output, opt.b)
      trainRNN(model, crit, embedding, training_input, training_output, valid_kaggle_input, valid_kaggle_output, space_idx, padding_idx, opt.sequence_length,  opt.epochs, opt.optimizer, opt.eta, opt.hacks_wanted)
      collectgarbage()
      local predictions, log_probs = rnn_greedily_segment(flat_valid_input, model, space_idx)
      local accuracy = prediction_accuracy(predictions, flat_valid_output)
      local precision = prediction_precision(predictions, flat_valid_output)
      local precision2 = prediction_precision2(predictions, flat_valid_output)
      local perp = perplexity(log_probs, flat_valid_output)
      collectgarbage()
      local valid_numbers = rnn_segment_and_count(valid_kaggle_input, model, space_idx, padding_idx)
      local mse = (valid_numbers - valid_kaggle_output):double():pow(2):mean()
      printoptions(opt)
      print("Results:", accuracy, precision, precision2, mse, perp)

    if (opt.testfile ~= '') then
      --print("Writing to test file")
      collectgarbage()
      local test_numbers = rnn_segment_and_count(test_input, model, space_idx, padding_idx)
      write_predictions(test_numbers, opt.testfile)
    end
      


   end



   -- Train.

   -- Test.
end

main()
