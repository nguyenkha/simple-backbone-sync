should = require 'should'
_ = require 'underscore'
backbone = require 'backbone'
client = require '../client'
Sync = client.Sync

# Test should be concentrate on target

describe '#ClientHandle', ->
  class Calculator extends backbone.Model
    plus: (a, b, callback) ->
      @handle.invoke 'plus', a, b, callback

  describe '#invoke', ->
    it 'should send method to server', (done) ->
      io = _.extend {}, backbone.Events
      s = new Sync io
      s.addNameToType 'Calculator', Calculator
      io.trigger 'register', 'c1', 'Calculator'
      m1 = s.getObjectByHandleId('c1')
      io.on 'invoke', (handleId, method, args, callback) -> 
        handleId.should.equal 'c1'
        method.should.equal 'plus'
        args[0].should.equal 1
        args[1].should.equal 2
        callback null, args[0] + args[1]
      
      m1.plus 1, 2, (err, result) ->
        if err
          done err
        else
          result.should.equal 3
          done()

describe 'ClientSync', ->
  s = io = null

  beforeEach (done) ->
    # Create new pool
    io = _.extend {}, backbone.Events
    s = new Sync io
    done()

  describe '#addType', ->
    class DebugElement extends backbone.Model

    it 'should create exactly type', ->
      s.addNameToType 'DebugElement', DebugElement
      io.trigger 'register', 'c1', 'DebugElement'
      s.getObjectByHandleId('c1').should.be.instanceOf DebugElement

    it 'should throw error unknown type', ->
      f = ->
        io.trigger 'register', 'c1', 'Thread'
      f.should.throw()

  describe '#onRegister', ->
    it 'should register new object', ->
      io.trigger 'register', 'c1', 'backbone.Model'
      s.getObjectByHandleId('c1').should.be.instanceOf backbone.Model
      io.trigger 'register', 'c2', 'backbone.Collection'
      s.getObjectByHandleId('c2').should.be.instanceOf backbone.Collection

  describe '#onModelSet', ->
    it 'should set simple data on registered object', ->
      io.trigger 'register', 'c1', 'backbone.Model'
      io.trigger 'model:set', 'c1', 
        foo:
          content: 'Hello world'
        id:
          content: 1
      s.getObjectByHandleId('c1').toJSON().should.eql
        foo: 'Hello world'
        id: 1

    it 'should set link on registered object', ->
      io.trigger 'register', 'c2', 'backbone.Model'
      io.trigger 'register', 'c1', 'backbone.Model'
      io.trigger 'model:set', 'c1', 
        foo:
          content: 'Hello world'
        id:
          content: 1
      io.trigger 'model:set', 'c2', 
        m1:
          handle: 'c1'
      m1 = s.getObjectByHandleId('c1') 
      m2 = s.getObjectByHandleId('c2') 
      m2.get('m1').should.equal m1

    it 'should notify when object change', (done) ->
      io.trigger 'register', 'c1', 'backbone.Model'
      io.trigger 'model:set', 'c1', 
        foo:
          content: 'Hello world'
        id:
          content: 1
      m1 = s.getObjectByHandleId 'c1'
      m1.on 'change', ->
        m1.get('foo').should.equal 'Kha 123'
        done()
      io.trigger 'model:set', 'c1', 
        foo:
          content: 'Kha 123'

  describe '#onCollectionAdd', ->
    it 'should notify when new model add to collection', (done) ->
      io.trigger 'register', 'c3', 'backbone.Collection'
      io.trigger 'register', 'c1', 'backbone.Model'
      io.trigger 'model:set', 'c1', 
        foo:
          content: 'Hello world'
        id:
          content: 1
      m1 = s.getObjectByHandleId('c1') 
      c1 = s.getObjectByHandleId('c3') 
      
      c1.on 'add', (model) ->
        model.should.equal m1
        done()

      io.trigger 'collection:add', 'c3', [ 'c1' ]

    it 'should notify when list of new models add to collection', (done) ->
      io.trigger 'register', 'c3', 'backbone.Collection'
      io.trigger 'register', 'c2', 'backbone.Model'
      io.trigger 'register', 'c1', 'backbone.Model'
      io.trigger 'model:set', 'c1', 
        foo:
          content: 'Hello world'
        id:
          content: 1
      io.trigger 'model:set', 'c2', 
        m1:
          handle: 'c1'
      m1 = s.getObjectByHandleId('c1') 
      m2 = s.getObjectByHandleId('c2') 
      c1 = s.getObjectByHandleId('c3') 
      
      c1.on 'add', (model) ->
        model.should.equal m1
        # Off all event
        c1.off()
        c1.on 'add', (model) ->
          model.should.equal m2
          c1.off()
          done()

      io.trigger 'collection:add', 'c3', [ 'c1', 'c2' ]

  describe '#onCollectionRemove', ->
    it 'should notify when model remove from collection', (done) ->
      io.trigger 'register', 'c3', 'backbone.Collection'
      io.trigger 'register', 'c1', 'backbone.Model'
      io.trigger 'model:set', 'c1', 
        foo:
          content: 'Hello world'
        id:
          content: 1
      io.trigger 'collection:add', 'c3', [ 'c1' ]    
      m1 = s.getObjectByHandleId('c1') 
      c1 = s.getObjectByHandleId('c3') 
      

      c1.on 'remove', (model) ->
        model.should.equal m1
        done()
      
      io.trigger 'collection:remove', 'c3', 'c1'

  describe '#onCollectionReset', ->
    it 'should notify when collection reset', (done) ->
      io.trigger 'register', 'c3', 'backbone.Collection'
      io.trigger 'register', 'c2', 'backbone.Model'
      io.trigger 'register', 'c1', 'backbone.Model'
      io.trigger 'model:set', 'c1', 
        foo:
          content: 'Hello world'
        id:
          content: 1
      io.trigger 'model:set', 'c2', 
        m1:
          handle: 'c1'
      io.trigger 'collection:add', 'c3', [ 'c1' ]
      m1 = s.getObjectByHandleId('c1') 
      m2 = s.getObjectByHandleId('c2') 
      c1 = s.getObjectByHandleId('c3') 
      
      c1.on 'remove', (model) ->
        throw Error('Shouldn\'t be here')
      c1.on 'reset', ->
        c1.length.should.equal 1
        c1.at(0).should.equal m2
        done()
      io.trigger 'collection:reset', 'c3', [ 'c2'] 