# USAGE: python analysis.py {all, SST1, SST2, TREC...} < SUMMARY_FILE
#   Ex: python analysis.py all < SUMMARY_FILE
#       python analysis.py TREC < SUMMARY_FILE
# To create summary file, do tail -n 2 * > SUMMARY_FILE in the directory being summarized
import numpy as np 
import pandas as pd 
import csv 
import sys

pd.set_option('expand_frame_repr', False)

sets = []
accuracies = []
assert(len(sys.argv) == 2)
print(sys.argv)


moreoutput=True


for line in sys.stdin:
    if line[0] == "=" or len(line) == 1 or line[0] == "W":
        continue
    if line[0] == 'R' and line[1] == "e":
        splitted = line.split('\t')
        print(splitted)
        if moreoutput:
            accuracies.append([float(splitted[1]), float(splitted[2]), float(splitted[3]), float(splitted[4]), float(splitted[5])])
        else:
            accuracies.append([float(splitted[1]), float(splitted[2])])
    if line[0] == 'D':
        splitted = line.split('\t')
        sets.append([splitted[1].split("HW3/")[1], splitted[3], splitted[5], splitted[7], splitted[9], splitted[11], splitted[13], splitted[15], splitted[17], splitted[19]])

print len(accuracies), len(sets)

#Datafile:       /n/home09/ankitgupta/CS287/CS287assignments/HW2/PTB.hdf5        Classifier:     lr      Alpha:  0       Eta:    50      Lambda: 0.1     Minibatch size: 2000    Num Epochs:     20      Optimizer:      sgd     Hidden Layers:  10      Embedding size: 50
#0.65331391114348

sets = np.array(sets)
accuracies = np.array(accuracies)
print sets.shape, accuracies.shape
#alldata = np.append(sets, accuracies[:, np.newaxis], axis=1)
alldata = np.append(sets, accuracies, axis=1)

df = pd.DataFrame(alldata)

if moreoutput:
    df.columns = ['Datafile', 'Classifier', 'Alpha', 'Eta', 'Lambda','MinibatchSize','NumEpochs', 'Optimizer', 'HiddenLayers', 'EmbeddingSize','Accuracy', 'SubsetCrossEnt', 'SubsetPerp', 'FullCrossEnt', 'FullPerp']
    df[['Accuracy', 'SubsetCrossEnt', 'SubsetPerp', 'FullCrossEnt', 'FullPerp']] = df[['Accuracy', 'SubsetCrossEnt', 'SubsetPerp', 'FullCrossEnt', 'FullPerp']].astype(float)
else:
    df.columns = ['Datafile', 'Classifier', 'Alpha', 'Eta', 'Lambda','MinibatchSize','NumEpochs', 'Optimizer', 'HiddenLayers', 'EmbeddingSize','Accuracy', 'SubsetCrossEnt']
    df[['Accuracy', 'SubsetCrossEnt']] = df[['Accuracy', 'SubsetCrossEnt']].astype(float)

df.sort(columns='SubsetCrossEnt', ascending=True, inplace=True)
if sys.argv[1] != "all":
    df = df[df['Datafile'].str.startswith(sys.argv[1])]

print df
print ""
print "Best nnpre ones"
print df[df['Classifier'] == 'nnpre']

print ""
print "Best lr ones"
print df[df['Classifier'] == 'lr']

print ""
print "Best nnfig1 ones"
print df[df['Classifier'] == 'nnfig1']


