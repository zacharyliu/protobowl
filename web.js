// Generated by CoffeeScript 1.3.3
var Question, QuestionSchema, QuizRoom, app, categories, checkAnswer, countCache, countQuestions, crypto, cumsum, db, difficulties, error_question, express, fisher_yates, fs, getQuestion, http, io, log, mongoose, parseCookie, port, rooms, scheduledUpdate, sha1, syllables, updateCache, uptime_begin, watcher,
  __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

express = require('express');

fs = require('fs');

checkAnswer = require('./lib/answerparse').checkAnswer;

syllables = require('./lib/syllable').syllables;

parseCookie = require('express/node_modules/connect').utils.parseCookie;

crypto = require('crypto');

app = express.createServer(express.logger());

io = require('socket.io').listen(app);

app.use(require('less-middleware')({
  src: __dirname
}));

app.use(express.favicon());

app.use(express.cookieParser());

app.use(express.session({
  secret: 'should probably make this more secretive',
  cookie: {
    httpOnly: false
  }
}));

app.use(express["static"](__dirname));

if (app.settings.env === 'development') {
  scheduledUpdate = null;
  updateCache = function() {
    return fs.readFile(__dirname + '/offline.appcache', 'utf8', function(err, data) {
      if (err) {
        throw err;
      }
      data = data.replace(/INSERT_DATE.*?\n/, 'INSERT_DATE ' + (new Date).toString() + "\n");
      return fs.writeFile(__dirname + '/offline.appcache', data, function(err) {
        if (err) {
          throw err;
        }
        io.sockets.emit('application_update', +(new Date));
        return scheduledUpdate = null;
      });
    });
  };
  watcher = function(event, filename) {
    if ((filename === "offline.appcache" || filename === "web.js" || filename === "web.coffee") || /\.css$/.test(filename)) {
      return;
    }
    console.log("changed file", filename);
    if (!scheduledUpdate) {
      return scheduledUpdate = setTimeout(updateCache, 500);
    }
  };
  fs.watch(__dirname, watcher);
  fs.watch(__dirname + "/lib", watcher);
  fs.watch(__dirname + "/less", watcher);
}

setTimeout(function() {
  return io.sockets.emit('application_update', +(new Date));
}, 1000 * 30);

io.configure(function() {
  io.set("log level", 2);
  return io.set("authorization", function(data, fn) {
    var cookie;
    if (!data.headers.cookie) {
      return fn('No cookie header', false);
    }
    cookie = parseCookie(data.headers.cookie);
    if (cookie) {
      console.log("GOT COOKIE", data.headers.cookie);
      data.sessionID = cookie['connect.sid'];
      fn(null, true);
    }
    return fn('No cookie found', false);
  });
});

app.set('views', __dirname);

app.set('view options', {
  layout: false
});

mongoose = require('mongoose');

db = mongoose.createConnection('mongodb://nodejitsu:87a9e43f3edd8929ef1e48ede1f0fc6d@alex.mongohq.com:10056/nodejitsudb560367656797');

QuestionSchema = new mongoose.Schema({
  category: String,
  num: Number,
  tournament: String,
  question: String,
  answer: String,
  difficulty: String,
  year: Number,
  round: String,
  random_loc: {
    type: [Number, Number],
    index: '2d'
  }
});

Question = db.model('Question', QuestionSchema);

fisher_yates = function(i) {
  var arr, j, _i, _ref, _results;
  if (i === 0) {
    return [];
  }
  arr = (function() {
    _results = [];
    for (var _i = 0; 0 <= i ? _i < i : _i > i; 0 <= i ? _i++ : _i--){ _results.push(_i); }
    return _results;
  }).apply(this);
  while (--i) {
    j = Math.floor(Math.random() * (i + 1));
    _ref = [arr[j], arr[i]], arr[i] = _ref[0], arr[j] = _ref[1];
  }
  return arr;
};

error_question = {
  'category': '$0x40000',
  'difficulty': 'segmentation fault',
  'num': 'NaN',
  'tournament': 'Guru Meditation Cup',
  'question': 'This type of event occurs when the queried database returns an invalid question and is frequently indicative of a set of constraints which yields a null set. Certain manifestations of this kind of event lead to significant monetary loss and often result in large public relations campaigns to recover from the damaged brand valuation. This type of event is most common with computer software and hardware, and one way to diagnose this type of event when it happens on the bootstrapping phase of a computer operating system is by looking for the POST information. Kernel varieties of this event which are unrecoverable are referred to as namesake panics in the BSD/Mach hybrid microkernel which powers Mac OS X. The infamous Disk Operating System variety of this type of event is known for its primary color backdrop and continues to plague many of the contemporary descendents of DOS with code names such as Whistler, Longhorn and Chidori. For 10 points, name this event which happened right now.',
  'answer': 'error',
  'year': 1970,
  'round': '0x080483ba'
};

getQuestion = function(difficulty, category, cb) {
  var criterion, rand;
  rand = Math.random();
  criterion = {
    random_loc: {
      $near: [rand, 0]
    }
  };
  if (difficulty) {
    criterion.difficulty = difficulty;
  }
  if (category) {
    criterion.category = category;
  }
  return Question.findOne(criterion, function(err, doc) {
    if (doc === null) {
      cb(error_question);
      return;
    }
    console.log("RANDOM PICK", rand, doc.random_loc[0], doc.random_loc[0] - rand);
    if (cb) {
      return cb(doc);
    }
  });
};

countCache = {};

countQuestions = function(difficulty, category, cb) {
  var criterion, id;
  id = difficulty + '-' + category;
  if (id in countCache) {
    return cb(countCache[id]);
  }
  criterion = {};
  if (difficulty) {
    criterion.difficulty = difficulty;
  }
  if (category) {
    criterion.category = category;
  }
  return Question.count(criterion, function(err, doc) {
    countCache[id] = doc;
    return cb(doc);
  });
};

categories = [];

difficulties = [];

Question.collection.distinct('category', function(err, docs) {
  return categories = docs;
});

Question.collection.distinct('difficulty', function(err, docs) {
  return difficulties = docs;
});

Question.collection.ensureIndex({
  random: 1,
  category: 1,
  difficulty: 1,
  random_loc: '2d'
});

cumsum = function(list, rate) {
  var num, sum, _i, _len, _ref, _results;
  sum = 0;
  _ref = [1].concat(list).slice(0, -1);
  _results = [];
  for (_i = 0, _len = _ref.length; _i < _len; _i++) {
    num = _ref[_i];
    _results.push(sum += Math.round(num) * rate);
  }
  return _results;
};

QuizRoom = (function() {

  function QuizRoom(name) {
    this.name = name;
    this.answer_duration = 1000 * 5;
    this.time_offset = 0;
    this.rate = 1000 * 60 / 5 / 200;
    this.__timeout = -1;
    this.freeze();
    this.new_question();
    this.users = {};
    this.difficulty = '';
    this.category = '';
    this.question_schedule = [];
    this.history = [];
  }

  QuizRoom.prototype.reset_schedule = function() {
    var _this = this;
    return countQuestions(this.difficulty, this.category, function(num) {
      if (num < 300) {
        return _this.question_schedule = fisher_yates(num);
      } else {
        return _this.question_schedule = [];
      }
    });
  };

  QuizRoom.prototype.get_question = function(cb) {
    var attemptQuestion, num_attempts,
      _this = this;
    num_attempts = 0;
    attemptQuestion = function() {
      num_attempts++;
      return getQuestion(_this.difficulty, _this.category, function(question) {
        var _ref;
        if ((_ref = question._id.toString(), __indexOf.call(_this.history, _ref) >= 0) && num_attempts < 15) {
          return attemptQuestion();
        }
        _this.history.splice(100);
        _this.history.splice(0, 0, question._id.toString());
        return cb(question);
      });
    };
    return countQuestions(this.difficulty, this.category, function(num) {
      var criterion, index;
      if (num < 300) {
        if (_this.question_schedule.length === 0) {
          _this.question_schedule = fisher_yates(num);
        }
        index = _this.question_schedule.shift();
        criterion = {};
        if (_this.difficulty) {
          criterion.difficulty = _this.difficulty;
        }
        if (_this.category) {
          criterion.category = _this.category;
        }
        console.log('FISHER YATES SCHEDULED', index, 'REMAINING', _this.question_schedule.length);
        return Question.find(criterion).skip(index).limit(1).exec(function(err, docs) {
          return cb(docs[0] || error_question);
        });
      } else {
        return attemptQuestion();
      }
    });
  };

  QuizRoom.prototype.add_socket = function(id, socket) {
    var user;
    if (!(id in this.users)) {
      this.users[id] = {
        sockets: [],
        guesses: 0,
        interrupts: 0,
        early: 0,
        correct: 0,
        last_action: 0
      };
    }
    user = this.users[id];
    user.id = id;
    user.last_action = this.serverTime();
    if (__indexOf.call(user.sockets, socket) < 0) {
      return user.sockets.push(socket);
    }
  };

  QuizRoom.prototype.vote = function(id, action, val) {
    this.users[id][action] = val;
    return this.sync();
  };

  QuizRoom.prototype.touch = function(id) {
    return this.users[id].last_action = this.serverTime();
  };

  QuizRoom.prototype.del_socket = function(id, socket) {
    var sock, user;
    user = this.users[id];
    if (user) {
      return user.sockets = (function() {
        var _i, _len, _ref, _results;
        _ref = user.sockets;
        _results = [];
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          sock = _ref[_i];
          if (sock !== socket) {
            _results.push(sock);
          }
        }
        return _results;
      })();
    }
  };

  QuizRoom.prototype.time = function() {
    if (this.time_freeze) {
      return this.time_freeze;
    } else {
      return this.serverTime() - this.time_offset;
    }
  };

  QuizRoom.prototype.serverTime = function() {
    return +(new Date);
  };

  QuizRoom.prototype.freeze = function() {
    return this.time_freeze = this.time();
  };

  QuizRoom.prototype.unfreeze = function() {
    if (this.time_freeze) {
      this.set_time(this.time_freeze);
      return this.time_freeze = 0;
    }
  };

  QuizRoom.prototype.set_time = function(ts) {
    return this.time_offset = new Date - ts;
  };

  QuizRoom.prototype.pause = function() {
    if (!(this.attempt || this.time() > this.end_time)) {
      return this.freeze();
    }
  };

  QuizRoom.prototype.unpause = function() {
    if (!this.attempt) {
      return this.unfreeze();
    }
  };

  QuizRoom.prototype.timeout = function(metric, time, callback) {
    var diff,
      _this = this;
    this.clear_timeout();
    diff = time - metric();
    if (diff < 0) {
      return callback();
    } else {
      return this.__timeout = setTimeout(function() {
        return _this.timeout(metric, time, callback);
      }, diff);
    }
  };

  QuizRoom.prototype.clear_timeout = function() {
    return clearTimeout(this.__timeout);
  };

  QuizRoom.prototype.new_question = function() {
    var _this = this;
    this.generating_question = true;
    return this.get_question(function(question) {
      var word;
      delete _this.generating_question;
      _this.attempt = null;
      _this.info = {
        category: question.category,
        difficulty: question.difficulty,
        tournament: question.tournament,
        num: question.num,
        year: question.year,
        round: question.round
      };
      _this.question = question.question.replace(/FTP/g, 'For 10 points').replace(/^\[.*?\]/, '').replace(/\n/g, ' ').replace(/\s+/g, ' ');
      _this.answer = question.answer.replace(/\<\w\w\>/g, '').replace(/\[\w\w\]/g, '');
      _this.begin_time = _this.time();
      _this.timing = (function() {
        var _i, _len, _ref, _results;
        _ref = this.question.split(" ");
        _results = [];
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          word = _ref[_i];
          _results.push(syllables(word) + 1);
        }
        return _results;
      }).call(_this);
      _this.set_speed(_this.rate);
      return _this.sync(2);
    });
  };

  QuizRoom.prototype.set_speed = function(rate) {
    var done, duration, elapsed, new_duration, now, remainder;
    now = this.time();
    this.cumulative = cumsum(this.timing, this.rate);
    elapsed = now - this.begin_time;
    duration = this.cumulative[this.cumulative.length - 1];
    done = elapsed / duration;
    remainder = 0;
    if (done > 1) {
      remainder = elapsed - duration;
      done = 1;
    }
    this.rate = rate;
    this.cumulative = cumsum(this.timing, this.rate);
    new_duration = this.cumulative[this.cumulative.length - 1];
    this.begin_time = now - new_duration * done - remainder;
    return this.end_time = this.begin_time + new_duration + this.answer_duration;
  };

  QuizRoom.prototype.skip = function() {
    return this.new_question();
  };

  QuizRoom.prototype.next = function() {
    if (this.time() > this.end_time - this.answer_duration && !this.generating_question) {
      return this.new_question();
    }
  };

  QuizRoom.prototype.emit = function(name, data) {
    return io.sockets["in"](this.name).emit(name, data);
  };

  QuizRoom.prototype.end_buzz = function(session) {
    var _ref,
      _this = this;
    if (((_ref = this.attempt) != null ? _ref.session : void 0) !== session) {
      return;
    }
    this.touch(this.attempt.user);
    if (!this.attempt.prompt) {
      this.clear_timeout();
      this.attempt.done = true;
      this.attempt.correct = checkAnswer(this.attempt.text, this.answer, this.question);
      log('buzz', [this.name, this.attempt.user, this.attempt.text, this.answer, this.attempt.correct]);
      if (Math.random() > 0.999) {
        this.attempt.correct = "prompt";
        this.sync();
        this.attempt.prompt = true;
        this.attempt.done = false;
        this.attempt.realTime = this.serverTime();
        this.attempt.start = this.time();
        this.attempt.text = '';
        this.attempt.duration = 10 * 1000;
        this.timeout(this.serverTime, this.attempt.realTime + this.attempt.duration, function() {
          return _this.end_buzz(session);
        });
      }
      this.sync();
    } else {
      this.attempt.done = true;
      this.attempt.correct = checkAnswer(this.attempt.text, this.answer, this.question);
      this.sync();
    }
    if (this.attempt.done) {
      this.unfreeze();
      if (this.attempt.correct) {
        this.users[this.attempt.user].correct++;
        if (this.attempt.early) {
          this.users[this.attempt.user].early++;
        }
        this.set_time(this.end_time);
      } else if (this.attempt.interrupt) {
        this.users[this.attempt.user].interrupts++;
      }
      this.attempt = null;
      return this.sync(1);
    }
  };

  QuizRoom.prototype.buzz = function(user, fn) {
    var early_index, session,
      _this = this;
    this.touch(user);
    if (this.attempt === null && this.time() <= this.end_time) {
      if (fn) {
        fn('http://www.whosawesome.com/');
      }
      session = Math.random().toString(36).slice(2);
      early_index = this.question.replace(/[^ \*]/g, '').indexOf('*');
      this.attempt = {
        user: user,
        realTime: this.serverTime(),
        start: this.time(),
        duration: 8 * 1000,
        session: session,
        text: '',
        early: early_index !== -1 && this.time() < this.begin_time + this.cumulative[early_index],
        interrupt: this.time() < this.end_time - this.answer_duration,
        done: false
      };
      this.users[user].guesses++;
      this.freeze();
      this.sync(1);
      return this.timeout(this.serverTime, this.attempt.realTime + this.attempt.duration, function() {
        return _this.end_buzz(session);
      });
    } else {
      if (fn) {
        return fn('THE GAME');
      }
    }
  };

  QuizRoom.prototype.guess = function(user, data) {
    var _ref;
    this.touch(user);
    if (((_ref = this.attempt) != null ? _ref.user : void 0) === user) {
      this.attempt.text = data.text;
      if (data.done) {
        console.log('omg done clubs are so cool ~ zuck');
        return this.end_buzz(this.attempt.session);
      } else {
        return this.sync();
      }
    }
  };

  QuizRoom.prototype.sync = function(level) {
    var attr, blacklist, data, id, user, user_blacklist;
    if (level == null) {
      level = 0;
    }
    data = {
      real_time: +(new Date),
      voting: {}
    };
    blacklist = ["name", "question", "answer", "timing", "voting", "info", "cumulative", "users", "question_schedule", "history", "__timeout"];
    user_blacklist = ["sockets"];
    for (attr in this) {
      if (typeof this[attr] !== 'function' && __indexOf.call(blacklist, attr) < 0) {
        data[attr] = this[attr];
      }
    }
    if (level >= 1) {
      data.users = (function() {
        var _results;
        _results = [];
        for (id in this.users) {
          if (!(!this.users[id].ninja)) {
            continue;
          }
          user = {};
          for (attr in this.users[id]) {
            if (__indexOf.call(user_blacklist, attr) < 0) {
              user[attr] = this.users[id][attr];
            }
          }
          user.online = this.users[id].sockets.length > 0;
          _results.push(user);
        }
        return _results;
      }).call(this);
    }
    if (level >= 2) {
      data.question = this.question;
      data.answer = this.answer;
      data.timing = this.timing;
      data.info = this.info;
    }
    if (level >= 3) {
      data.categories = categories;
      data.difficulties = difficulties;
    }
    return io.sockets["in"](this.name).emit('sync', data);
  };

  return QuizRoom;

})();

sha1 = function(text) {
  var hash;
  hash = crypto.createHash('sha1');
  hash.update(text);
  return hash.digest('hex');
};

http = require('http');

log = function(action, obj) {
  var req;
  req = http.request({
    host: 'inception.pi.antimatter15.com',
    port: 3140,
    path: '/log',
    method: 'POST'
  }, function() {
    return console.log("saved log");
  });
  req.on('error', function() {
    return console.log("logging error");
  });
  req.write((+(new Date)) + ' ' + action + ' ' + JSON.stringify(obj) + '\n');
  return req.end();
};

rooms = {};

io.sockets.on('connection', function(sock) {
  var publicID, room, sessionID,
    _this = this;
  sessionID = sock.handshake.sessionID;
  publicID = null;
  room = null;
  sock.on('join', function(data, fn) {
    var room_name;
    if (data.old_socket && io.sockets.socket(data.old_socket)) {
      io.sockets.socket(data.old_socket).disconnect();
    }
    room_name = data.room_name;
    if (data.ninja) {
      publicID = '__secret_ninja';
    } else {
      publicID = sha1(sessionID + room_name);
    }
    if (data.god) {
      publicID += "_god";
      for (room in rooms) {
        sock.join(room);
      }
    } else {
      sock.join(room_name);
    }
    if (!(room_name in rooms)) {
      rooms[room_name] = new QuizRoom(room_name);
    }
    room = rooms[room_name];
    room.add_socket(publicID, sock.id);
    if (data.ninja) {
      room.users[publicID].ninja = true;
      room.users[publicID].name = publicID;
    }
    if (!('name' in room.users[publicID])) {
      room.users[publicID].name = require('./lib/names').generateName();
    }
    fn({
      id: publicID,
      name: room.users[publicID].name
    });
    room.sync(3);
    if (!data.ninja) {
      return room.emit('log', {
        user: publicID,
        verb: 'joined the room'
      });
    }
  });
  sock.on('echo', function(data, callback) {
    return callback(+(new Date));
  });
  sock.on('rename', function(name) {
    room.users[publicID].name = name;
    room.touch(publicID);
    if (room) {
      return room.sync(1);
    }
  });
  sock.on('skip', function(vote) {
    return room.skip();
  });
  sock.on('next', function() {
    return room.next();
  });
  sock.on('pause', function(vote) {
    room.pause();
    if (room) {
      return room.sync();
    }
  });
  sock.on('unpause', function(vote) {
    room.unpause();
    if (room) {
      return room.sync();
    }
  });
  sock.on('difficulty', function(data) {
    room.difficulty = data;
    room.reset_schedule();
    room.sync();
    log('difficulty', [room.name, publicID, room.difficulty]);
    return countQuestions(room.difficulty, room.category, function(count) {
      return room.emit('log', {
        user: publicID,
        verb: 'set difficulty to ' + (data || 'everything') + ' (' + count + ' questions)'
      });
    });
  });
  sock.on('category', function(data) {
    room.category = data;
    room.reset_schedule();
    room.sync();
    log('category', [room.name, publicID, room.category]);
    return countQuestions(room.difficulty, room.category, function(count) {
      return room.emit('log', {
        user: publicID,
        verb: 'set category to ' + (data.toLowerCase() || 'potpourri') + ' (' + count + ' questions)'
      });
    });
  });
  sock.on('speed', function(data) {
    room.set_speed(data);
    return room.sync();
  });
  sock.on('buzz', function(data, fn) {
    if (room) {
      return room.buzz(publicID, fn);
    }
  });
  sock.on('guess', function(data) {
    if (room) {
      return room.guess(publicID, data);
    }
  });
  sock.on('chat', function(_arg) {
    var done, session, text;
    text = _arg.text, done = _arg.done, session = _arg.session;
    if (room) {
      room.touch(publicID);
      if (done) {
        log('chat', [room.name, publicID, text]);
      }
      return room.emit('chat', {
        text: text,
        session: session,
        user: publicID,
        done: done,
        time: room.serverTime()
      });
    }
  });
  sock.on('resetscore', function() {
    var u;
    if (room && room.users[publicID]) {
      u = room.users[publicID];
      u.interrupts = u.guesses = u.correct = u.early = 0;
      return room.sync(1);
    }
  });
  sock.on('report_question', function(data) {
    return log('report_question', data);
  });
  sock.on('report_answer', function(data) {
    return log('report_answer', data);
  });
  return sock.on('disconnect', function() {
    console.log("someone", publicID, sock.id, "left");
    if (room) {
      log('disconnect', [room.name, publicID, sock.id]);
      room.del_socket(publicID, sock.id);
      room.sync(1);
      if (room.users[publicID].sockets.length === 0 && !room.users[publicID].ninja) {
        return room.emit('log', {
          user: publicID,
          verb: 'left the room'
        });
      }
    }
  });
});

uptime_begin = +(new Date);

app.post('/stalkermode/update', function(req, res) {
  console.log('triggering application update check');
  io.sockets.emit('application_update', +(new Date));
  return res.redirect('/stalkermode');
});

app.post('/stalkermode/forceupdate', function(req, res) {
  console.log('forcing application update');
  io.sockets.emit('application_force_update', +(new Date));
  return res.redirect('/stalkermode');
});

app.post('/stalkermode/announce', express.bodyParser(), function(req, res) {
  io.sockets.emit('chat', {
    text: req.body.message,
    session: Math.random().toString(36).slice(3),
    user: '__' + req.body.name,
    done: true,
    time: +(new Date)
  });
  return res.redirect('/stalkermode');
});

app.get('/stalkermode', function(req, res) {
  var util;
  util = require('util');
  return res.render('admin.jade', {
    env: app.settings.env,
    mem: util.inspect(process.memoryUsage()),
    start: uptime_begin,
    rooms: rooms
  });
});

app.get('/new', function(req, res) {
  return res.redirect('/' + require('./lib/names').generatePage());
});

app.get('/', function(req, res) {
  return res.redirect('/lobby');
});

app.get('/:channel', function(req, res) {
  var name;
  name = req.params.channel;
  return res.render('index.jade', {
    name: name,
    env: app.settings.env
  });
});

port = process.env.PORT || 5000;

app.listen(port, function() {
  return console.log("listening on", port);
});
