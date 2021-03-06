#!/usr/bin/env python

"""NER Preprocessing
Feature converters take in padded sentence, index, and window size

0. Load tag dict
1. Go through dataset once
    -Create vocab with top 100000 (lowercase) words
    -Initialize features (unigram feature)
        -Unigram feature should take sentence, output sparse indices (handle RARE here)
        -Capitalization feature does not need to see the dataset
2. Go through dataset again
    -For each sentence, add padding and handle NUMBER
        -For each word, apply sparse and dense feature converters
        -Add NER index to Y
    -Output X_sparse, X_dense, Y
3. Save to hdf5:
    -'train_input_sparse'
    -'train_input_dense'
    -'train_output'
    -'valid_input_sparse'
    -'valid_input_dense'
    -'valid_output'
    -'test_input_sparse'
    -'test_input_dense'
"""
from collections import defaultdict
from features import *

import numpy as np
import h5py
import argparse
import sys
import random
import re
import codecs


def load_tag_dict(file_path, front_tag="<t>", back_tag="</t>"):
    tag_dict = {}
    with open(file_path, 'r') as f:
        for line in f:
            tag, idx = line.strip().split(' ')
            tag_dict[tag] = int(idx)

    tag_dict[front_tag] = max(tag_dict.values())+1
    tag_dict[back_tag] = max(tag_dict.values())+1

    return tag_dict

def parse_line(s, num_sub="NUMBER", lowercase=False, sep='\t'):
    assert s[0].isdigit()
    s = s.strip()
    try:
        global_id, sentence_id, word, tag = s.split(sep)
    # test file has no tag
    except ValueError:
        tag = None
        global_id, sentence_id, word = s.split(sep)
    if lowercase:
        word = word.lower()
    word = re.sub('\d', num_sub, word)
    return word, tag


def init_vocab(file_path, top_n=100000, front_word="<s>", back_word="</s>"):
    vocab_dict = defaultdict(int)

    with open(file_path, 'r') as f:
        for line in f:
            if line[0].isdigit():
                word, _ = parse_line(line, lowercase=True)
                vocab_dict[word] += 1    

    top_n_words = sorted(vocab_dict, key=vocab_dict.get, reverse=True)[:top_n]
    return [front_word, back_word]+top_n_words+['RARE', '<FRONTPADDING>', '<BACKPADDING>']


def init_features(feature_list):
    inited_features = []
    numSparseFeatures = 0
    numDenseFeatures = 0
    index_offset = 1

    for feature in feature_list:
        if type(feature) is tuple:
            kwargs = feature[1]
            feature = feature[0]
        else:
            kwargs = {}

        kwargs['index_offset'] = index_offset

        inited_feature = feature(**kwargs)
        inited_feature.initialize()
        inited_features.append(inited_feature)

        if inited_feature.isSparse():
            numSparseFeatures += inited_feature.maxFeatIdx()
            index_offset += inited_feature.maxFeatIdx()+1
        else:
            numDenseFeatures += inited_feature.numFeats()

    return inited_features, numSparseFeatures, numDenseFeatures

def load_padded_sentences(data_file, dwin, sep, front_word="<s>", back_word="</s>"):
    all_sentences = []
    this_sentence = ['<FRONTPADDING>' for _ in range(dwin/2)]+[front_word]

    with open(data_file, 'r') as f:
        for line in f:
            if line[0].isdigit():
                word, _ = parse_line(line, sep=sep)
                this_sentence.append(word)
            # NEW SENTENCE!
            else:
                # finish the old
                this_sentence = this_sentence + [back_word]+['<BACKPADDING>' for _ in range(dwin/2)]
                all_sentences.append(this_sentence)
                this_sentence = ['<FRONTPADDING>' for _ in range(dwin/2)]+[front_word]

    return all_sentences

def create_input(data_file, dwin, features, sep='\t'):
    sparse_features = [f for f in features if f.isSparse()]
    dense_features = [f for f in features if not f.isSparse()]
    padded_sentences = load_padded_sentences(data_file, dwin, sep)
    sparse_X = []
    dense_X = []

    for sentence in padded_sentences:
        start = dwin/2
        end = len(sentence)-dwin/2-1
        for i in range(start, end+1):

            these_sparse_feats = []
            for sparse_feat in sparse_features:
                feat = sparse_feat.convert(sentence, i)
                these_sparse_feats.extend(feat)
            
            sparse_X.append(these_sparse_feats)

            these_dense_feats = []
            for dense_feat in dense_features:
                feat = dense_feat.convert(sentence, i)
                these_dense_feats.extend(feat)
            
            dense_X.append(these_dense_feats)

    return sparse_X, dense_X


def create_output(data_file, tag_dict):
    Y = [tag_dict['<t>']]

    with open(data_file, 'r') as f:
        for line in f:
            if line[0].isdigit():
                _, tag = parse_line(line)
                try:
                    Y.append(tag_dict[tag])
                except KeyError:
                    print line
                    print tag
                    assert False
            else:
                Y.append(tag_dict['</t>'])
                Y.append(tag_dict['<t>'])

    # take out the last sentence
    popped = Y.pop()
    while popped != tag_dict['<t>']:
        popped = Y.pop()

    return Y



FILE_PATHS = {"CONLL": ("data/train.num.txt",
                        "data/dev.num.txt",
                        "data/test.num.txt",
                        "data/tags.txt")}
args = {}

WORD_EMBEDDINGS_FILE = None


def main(arguments):
    global args
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('dataset', help="Data set",
                        type=str)
    parser.add_argument('dwin', help="Window size",
                        type=int, nargs='?', default=1)
    parser.add_argument('-u', help="Unigram features only",
                        action="store_true", default=False)
    args = parser.parse_args(arguments)
    dataset = args.dataset
    dwin = args.dwin
    unigrams_only = args.u
    train, valid, test, tag_file = FILE_PATHS[dataset]

    # Force window size odd
    assert dwin > 0 and dwin % 2 == 1

    # Load tag dict
    print "Loading tag dict..."
    tag_dict = load_tag_dict(tag_file)
    # Initialize vocabulary, a list of words
    if WORD_EMBEDDINGS_FILE is not None:
        print "Initializing vocabulary (and word embeddings)..."
        vocab, word_embeddings = init_vocab_and_embeddings(WORD_EMBEDDINGS_FILE, 500000)
    else:
        print "Initializing vocabulary..."
        vocab = init_vocab(train)
        word_embeddings = None
    # Initialize features
    print "Initializing features..."
    if unigrams_only:
        feat_list = [(UnigramFeature, {'vocab': vocab, 'dwin': dwin})]
    else:
        feat_list = [(StemFeature, {'vocab': vocab, 'dwin': dwin}), (POSFeature, {'dwin': dwin}), (UnigramFeature, {'vocab': vocab, 'dwin': dwin}), (CapitalizationFeature, {'dwin': dwin})]
    features, numSparseFeatures, numDenseFeatures = init_features(feat_list)

    numClasses = len(tag_dict)
    print "sparse, dense, classes:"
    print numSparseFeatures, numDenseFeatures, numClasses

    sparse_Xs = []
    dense_Xs = []
    Ys = []

    for i, data_file in enumerate([train, valid, test]):
        # Create sparse and dense inputs
        print "Creating input from "+data_file
        if i < 2:
            sparse_X, dense_X = create_input(data_file, dwin, features)
        # annoying discrepancy with the test file
        else:
            sparse_X, dense_X = create_input(data_file, dwin, features, sep=None)
        sparse_Xs.append(sparse_X)
        dense_Xs.append(dense_X)

        if i < 2:
            # Create output (POS tags)
            print "Creating output"
            Y = create_output(data_file, tag_dict)
            Ys.append(Y)

    # Write out to hdf5
    print "Writing out to hdf5"
    filename = args.dataset + '_'+str(dwin)+'.hdf5'
    with h5py.File(filename, "w") as f:
        for i, data_name in enumerate(['train', 'valid', 'test']):
            
            f[data_name+'_sparse_input'] = sparse_Xs[i]
            f[data_name+'_dense_input'] = dense_Xs[i]
            
            if data_name != 'test':
                f[data_name+'_output'] = Ys[i]

        if word_embeddings is not None:
            f['word_embeddings'] = word_embeddings
        else:
            f['word_embeddings'] = np.array([0], dtype=np.int32)
        f['numSparseFeatures'] = np.array([numSparseFeatures], dtype=np.int32)
        f['numDenseFeatures'] = np.array([numDenseFeatures], dtype=np.int32)
        f['numClasses'] = np.array([numClasses], dtype=np.int32)
        f['startClass'] = np.array([tag_dict['<t>']], dtype=np.int32)
        f['endClass'] = np.array([tag_dict['</t>']], dtype=np.int32)
        f['dwin'] = np.array([dwin], dtype=np.int32)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
