// Generated by CoffeeScript 1.3.3
var checkAnswer, fs, nextQuestion, parseAnswer, readline, z;

fs = require('fs');

readline = require('readline');

checkAnswer = require('./answerparse').checkAnswer;

parseAnswer = require('./answerparse').parseAnswer;

nextQuestion = function() {
  var answer;
  answer = answers.shift();
  return rl.question(answer, function(resp) {
    var answ, opt, _i, _len, _ref;
    _ref = resp.split(',');
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      opt = _ref[_i];
      answ = checkAnswer(opt, answer);
      console.log("judgement", answ);
      console.log("--------------------");
    }
    return nextQuestion();
  });
};

z = function(a, b) {
  return console.log(checkAnswer(a, b));
};

z('shay\'s rebellion', 'bacons rebellion');

z('haymarket', 'haymarket square');

z('feynman', 'Richard Feynman');

z('fineman', 'Richard Feynman');

z('circumsize', 'circumsision');

z('circumsise', 'circumsision');

z('science', 'scientology');

z('scientology', 'science');

z('al gore', 'albert al gore');

z('cage', 'John Cage');

z('nicolas cage', 'John Cage');

z('locke', 'john locke');

z('blake', 'William Blake');

z('hangover', 'The Hangover');

z('curcible', 'The Crucible');

z("cortez", "Hernan Cortes de Monroy y Pizarro, First Marques del Valle de Oaxaca");

z("hernando", "Hernan Cortes de Monroy y Pizarro, First Marques del Valle de Oaxaca");

z("13 ways of looking at a blackbird", "Thirteen Ways of Looking at a Blackbird");

z("Frost", "Robert Lee Frost");

z("Robert", "Robert Lee Frost");

z("rawls", "John Rawls");

z("Hume", 'David Hume');

z("The Woolf", "Virginia Woolf");

z("jaialai", "jai alai (HI-ah-LIE)");

z("paramagnetic", "paramagnetism");

z("sheild", "shields");

z("Pierre Renoir", "Pierre-Auguste Renoir");

z("Taft", "Robert Taft");

z("Atwell", "Margaret Atwood");

z("os x", "Mac OSX [or Macintosh Operating System Ten; accept letter-by-letter pronunciations of");

z("osx", "Mac OSX [or Macintosh Operating System Ten; accept letter-by-letter pronunciations of");

z("house of lords", "The House of Lords [or The House of Lords Spiritual and Temporal or The House of Peers]");

z('borobn', "boron [or B]");

z('acid', 'base');

z("luke", 'The Gospel According to Luke [or Gospel of Luke]');

z("kublai khan", 'An Lushan (accept An Luoshan or Ga Luoshan)');

z('1856', 'United States Presidential election of 1852');

z('1852', 'United States Presidential election of 1852');

z('tree', 'RAM [or random-access memory; prompt on memory; accept DRAM or dynamic');

z('poisson', 'Paul Cézanne');

z('chrysanthemum and the sword', 'The Chrysanthemum and the Sword: Patterns of Japanese Culture');

z("Debs", "Eugene Victor Debs");

z("Battle", "Battle of Bunker Hill [or Battle of Breed's Hill before it is read]");

z("Symphony in F", "Symphony in D minor");

z("B flat", "E flat");