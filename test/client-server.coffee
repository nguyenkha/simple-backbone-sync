should = require 'should'
_ = require 'underscore'
backbone = require 'backbone'
client = require '../client'
server = require '../server'
ClientSync = client.Sync
ServerSync = server.Sync
Handle = server.Handle

describe 'ClientHandle-ServerHandle integration', ->
  c = c1 = io = m1 = s = null

  class ClientCalculator extends backbone.Model
    @className: 'Calculator'

    plus: (a, b, callback) ->
      @handle.invoke 'plus', a, b, callback

  class ServerCalculator extends backbone.Model
    plus: (a, b, callback) ->
      callback null, a + b

  class ServerCalculatorHandle extends Handle
    @clazz: ServerCalculator
  
    @className: 'Calculator'

    @methods: [ 'plus' ]

    constructor: (id, sync, obj) ->
      super id, sync, obj

  beforeEach (done) ->
    # Create new pool
    io = _.extend {}, backbone.Events
    s = new ServerSync io
    c = new ClientSync io    
    m1 = new ServerCalculator()
    done()

  describe '#invoke', ->

    it 'should call remote server method', (done) ->
      c.addType ClientCalculator
      s.addType ServerCalculatorHandle
      s.register m1
      clientC1 = c.getObjectByHandleId m1.handle.id
      clientC1.plus 1, 2, (err, result) ->
        result.should.equal 3
        done err

describe 'ClientSync-ServerSync integration', ->
  c1 = io = m1 = m2 = m3 = c = s = null

  beforeEach (done) ->
    # Create new pool
    io = _.extend {}, backbone.Events
    s = new ServerSync io
    c = new ClientSync io
    
    m1 = new backbone.Model
      foo: 'Hello world'
      id: 1
      bar: { foo: { baz: 'Hello world' }, a: [1, 2, 3] }
      a: [1, 2, 3]

    m2 = new backbone.Model
      m1: m1
      id: 2

    m3 = new backbone.Model
      id: 3
      foo: 'Hello'
      bar: 'World'

    c1 = new backbone.Collection()
    # Pre-add m1, m3
    c1.add m1
    c1.add m3

    done()


  describe '#sync', ->
    it 'should sync new model on client', ->
      s.register m1
      c.getObjectByHandleId(m1.handle.id).toJSON().should.eql m1.toJSON()
      s.register m2
      c.getObjectByHandleId(m2.handle.id).get('m1').should.equal c.getObjectByHandleId(m1.handle.id)
      s.register c1
      clientC1 = c.getObjectByHandleId(c1.handle.id)
      clientC1.length.should.equal c1.length
      clientC1.at(0).toJSON().should.eql m1.toJSON()
      clientC1.at(1).toJSON().should.eql m3.toJSON()

    it 'should notify model change to client', (done) ->
      s.register m1
      clientM1 = c.getObjectByHandleId(m1.handle.id)
      clientM1.on 'change', ->
        clientM1.get('foo').should.equal m1.get('foo')
        done()
      m1.set 'foo', 'Kha 123'

    it 'should notify add new model to collection', (done) ->
      s.register c1
      clientC1 = c.getObjectByHandleId(c1.handle.id)
      clientC1.on 'add', (model) ->
        model.should.equal c.getObjectByHandleId(m2.handle.id)
        done()
      c1.add m2

    it 'should notify remove model from collection', (done) ->
      s.register c1
      clientC1 = c.getObjectByHandleId(c1.handle.id)
      clientC1.on 'remove', (model) ->
        model.should.equal c.getObjectByHandleId(m3.handle.id)
        done()
      c1.remove [ m3 ]

    it 'should notify reset collection', (done) ->
      s.register c1
      clientC1 = c.getObjectByHandleId(c1.handle.id)
      clientC1.on 'reset', (model) ->
        clientC1.length.should.equal c1.length
        clientC1.at(0).should.equal c.getObjectByHandleId(m2.handle.id)
        done()
      c1.reset [ m2 ]

