require 'nn'
require 'rnn'
require 'optim'

function nn_model(vocab_size, embedding_dim, window_size, hidden_size, output_dim)
	local model = nn.Sequential()
	local embedding = nn.LookupTable(vocab_size, embedding_dim)
	model:add(embedding)
	model:add(nn.View(-1):setNumInputDims(2))
	model:add(nn.Linear(embedding_dim*window_size, hidden_size))
	model:add(nn.HardTanh())
	model:add(nn.Linear(hidden_size, output_dim))
	model:add(nn.LogSoftMax())
	criterion = nn.ClassNLLCriterion()
	return model, criterion, embedding

end
function rnn(vocab_size, embed_dim, output_dim)
	batchLSTM = nn.Sequential()
	batchLSTM:add(nn.LookupTable(vocab_size, embed_dim)) --will return a sequence-length x batch-size x embedDim tensor

	-- 1 indicates the dimension we are splitting along. 3 indicates the number of dimensions in the input (allows for batching)
	batchLSTM:add(nn.SplitTable(1, 3)) --splits into a sequence-length table with batch-size x embedDim entries
	-- now let's add the LSTM stuff
	batchLSTM:add(nn.Sequencer(nn.LSTM(embed_dim, embed_dim)))
	batchLSTM:add(nn.Sequencer(nn.Linear(embed_dim, output_dim)))
	batchLSTM:add(nn.Sequencer(nn.LogSoftMax()))

	-- Add a criterion
	crit = nn.SequencerCriterion(nn.ClassNLLCriterion())

	return batchLSTM, crit
end

function trainNN(model, crit, training_input, training_output, minibatch_size, num_epochs, optimizer, minibatch_size, eta)
	local parameters, gradParameters = model:getParameters()

	for i = 1, num_epochs do
		print("Beginning epoch", i)
		for j = 1, training_input:size(1)-minibatch_size, minibatch_size do

		    -- zero out our gradients
		    gradParameters:zero()
		    model:zeroGradParameters()

		   	minibatch_inputs = training_input:narrow(1, j, minibatch_size)
		    minibatch_outputs = training_output:narrow(1, j, minibatch_size)

		    -- Create a closure for optim
		    local feval = function(x)
				-- Inspired by this torch demo: https://github.com/andresy/torch-demos/blob/master/train-a-digit-classifier/train-on-mnist.lua
				-- get new parameters
				if x ~= parameters then
					parameters:copy(x)
				end

				-- reset gradients
				gradParameters:zero()

				preds = model:forward(minibatch_inputs)
				loss = criterion:forward(preds, minibatch_outputs) --+ lambda*torch.norm(parameters,2)^2/2
				if j == 1 then
					print("    ", loss)
				end

				-- backprop
				dLdpreds = criterion:backward(preds, minibatch_outputs) -- gradients of loss wrt preds
				model:backward(minibatch_inputs, dLdpreds)


				return loss,gradParameters
			end

			-- Do the update operation.
	    	if optimizer == "adagrad" then
	    		config =  {
		    		learningRate = eta,
		    		weightDecay = lambda,
		    		learningRateDecay = 5e-7
	    		}
	    		optim.adagrad(feval, parameters, config)
	    	elseif optimizer == "sgd" then
	    		config = {
	    			learningRate = eta, 
	    		}
	    		optim.sgd(feval, parameters, config)
		    else 
		    	assert(false)
		    end

		end
	end
end


function trainRNN(model,
				criterion,
				training_input,
				training_output,
				l, 
				num_epochs,
				optimizer,
				eta)
	local parameters, gradParameters = model:getParameters()
	for i = 1, num_epochs do
		print("Beginning epoch", i)
		for j = 1, training_input:size(2)-l, l do

		    -- zero out our gradients
		    gradParameters:zero()
		    model:zeroGradParameters()

		   	minibatch_inputs = training_input:narrow(2, j, l):t()
		    minibatch_outputs = training_output:narrow(2, j, l):t()

		    -- Create a closure for optim
		    local feval = function(x)
				-- Inspired by this torch demo: https://github.com/andresy/torch-demos/blob/master/train-a-digit-classifier/train-on-mnist.lua
				-- get new parameters
				if x ~= parameters then
					parameters:copy(x)
				end

				-- reset gradients
				gradParameters:zero()

				preds = model:forward(minibatch_inputs)
				loss = criterion:forward(preds, minibatch_outputs) --+ lambda*torch.norm(parameters,2)^2/2
				if j == 1 then
					print("    ", loss)
				end

				-- backprop
				dLdpreds = criterion:backward(preds, minibatch_outputs) -- gradients of loss wrt preds
				model:backward(minibatch_inputs, dLdpreds)


				return loss,gradParameters
			end

			-- Do the update operation.
	    	if optimizer == "adagrad" then
	    		config =  {
		    		learningRate = eta,
		    		weightDecay = lambda,
		    		learningRateDecay = 5e-7
	    		}
	    		optim.adagrad(feval, parameters, config)
	    	elseif optimizer == "sgd" then
	    		config = {
	    			learningRate = eta, 
	    		}
	    		optim.sgd(feval, parameters, config)
		    else 
		    	assert(false)
		    end

		end
	end
end

function nn_greedily_segment(flat_valid_input, model, window_size, space_idx)

	print("Starting predictions")
	local valid_input_count = flat_valid_input:size(1)
	local valid_output_predictions = torch.ones(valid_input_count):long()
	local next_window = torch.Tensor(window_size):copy(flat_valid_input:narrow(1, 1, window_size))
	local next_word_idx = window_size+1

	while next_word_idx < valid_input_count do 

		if next_word_idx % 1000 == 0 then
			print("Word", next_word_idx)
		end

		local predictions = model:forward(next_window)
		
		-- shift the window
		for i=1, window_size-1 do
			next_window[i] = next_window[i+1]
		end

		-- predicting a space
		if (predictions[2] > torch.log(0.5)) then
			valid_output_predictions[next_word_idx-window_size] = 2
			next_window[window_size] = space_idx
		-- predicting a non-space, so grab the next valid input
		else
			next_window[window_size] = flat_valid_input[next_word_idx]
			next_word_idx = next_word_idx + 1
		end

	end

	return valid_output_predictions

end

function rnn_greedily_segment(flat_valid_input, model, space_idx)

	print("Starting predictions")
	model:evaluate()
	local valid_input_count = flat_valid_input:size(1)
	local valid_output_predictions = torch.ones(valid_input_count):long()
	local next_word_idx = 1
	local char = flat_valid_input:narrow(1, next_word_idx, 1)

	while next_word_idx < valid_input_count do 

		if next_word_idx % 1000 == 0 then
			print("Word", next_word_idx)
		end

		local predictions = model:forward(char)[1]
		--print(predictions)

		-- predicting a space
		if (predictions[2] > torch.log(0.5)) then
			--print('Space Found')
			valid_output_predictions[next_word_idx] = 2
			char = torch.LongTensor{space_idx}
		-- predicting a non-space, so grab the next valid input
		else
			next_word_idx = next_word_idx + 1
			char = flat_valid_input:narrow(1, next_word_idx, 1)
		end

	end

	return valid_output_predictions

end

function example()
	r, crit = rnn(100, 5, 2)

	-- batchsize = 5. SequenceLength = 3. 
	inputs = (torch.abs(torch.randn(5,3)*10) + 1):long()
	-- batchSize = 5. These outputs will be either 1 or 2.
	-- There are 3 of these, since ther eis one for every element in sequence.
	batch_output = torch.round(torch.rand(5)) + 1
	outputs = {batch_output, batch_output, batch_output}
	-- Make some predictions
	res = r:forward(inputs:t())
	print(res)
	loss = crit:forward(res, outputs)
	print(loss)
	dLdPreds = crit:backward(res, outputs)
	print(dLdPreds)
	r:backward(inputs:t(), dLdPreds)
end
--example()
