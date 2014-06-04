should = require 'should'
_ = require 'underscore'
backbone = require 'backbone'
server = require '../server'
Sync = server.Sync

describe 'ServerHandle', ->
  io = m1 = s = null

  class Calculator extends backbone.Model
    plus: (a, b, callback) ->
      callback null, a + b

    mul: (a, b, callback) ->
      callback Error('Error')

  beforeEach (done) ->
    # Create new pool
    io = _.extend {}, backbone.Events
    s = new Sync io
    m1 = new Calculator()
    done()
  
  describe '#invoke', ->
    it 'should process remote call (accept method)', (done) ->
      s.addTypeToName Calculator, 'Calculator', [ 'plus' ]
      s.register m1
      cb1 = (err, result) ->
        if err
          throw Error('Shouldn\' throw error')
        else
          result.should.equal 3

          cb2 = (err, result) ->
            if not err
              throw Error('Should throw error')
            else
              cb3 = (err, result) ->
                if not err
                  throw Error('Should throw error')
                else
                  done()
              # Non-exist object
              io.trigger 'invoke', '123', 'mul2', [1, 2], cb3     
          # Non-accept methods
          io.trigger 'invoke', m1.handle.id, 'mul', [1, 2], cb2
      # Work
      io.trigger 'invoke', m1.handle.id, 'plus', [1, 2], cb1 

describe 'ServerSync', ->
  c1 = io = m1 = m2 = m3 = s = null

  beforeEach (done) ->
    # Create new pool
    io = _.extend {}, backbone.Events
    s = new Sync io
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

  describe '#addType', ->
    # Simple class to test
    class DebugElement extends backbone.Model

    class Thread extends DebugElement

    class ThreadList extends backbone.Collection

    it 'should return real type if it had add', ->
      s.addTypeToName DebugElement, 'DebugElement'
      obj = new DebugElement()
      s.getTypeName(obj).should.equal 'DebugElement'

    it 'should return base type if not', ->
      obj = new Thread()
      s.getTypeName(obj).should.equal 'backbone.Model'
      obj = new ThreadList()
      s.getTypeName(obj).should.equal 'backbone.Collection'

  describe '#register', ->
    it 'should register simple backbone model object', (done) ->
      io.on 'register', (handleId1, type) ->
        handleId1.should.equal m1.handle.id
        type.should.equal 'backbone.Model'

        io.on 'model:set', (handleId2, links) ->
          handleId2.should.equal m1.handle.id
          links.id.content.should.equal m1.id
          links.foo.content.should.equal m1.get 'foo'
          links.bar.content.should.eql m1.get 'bar'
          links.a.content.should.eql m1.get 'a'

          io.off()

          c2 = new backbone.Collection()

          io.on 'register', (handleId3, type) ->
            handleId3.should.equal c2.handle.id
            type.should.equal 'backbone.Collection'
            done()

          s.register c2

      s.register m1

    it 'should register link backbone model object', (done) ->
      io.on 'register', (handleId1, type) ->
        # Register m2, do nothing
        handleId1.should.equal m2.handle.id
        io.off()
        io.on 'register', (handleId2, type) ->
          # Register m1
          handleId2.should.equal m1.handle.id
          io.off()
          io.on 'model:set', (handleId3, links) ->
            # Set m1
            handleId3.should.equal m1.handle.id
            io.off()
            io.on 'model:set', (handleId4, links) ->
              handleId4.should.equal m2.handle.id
              links.m1.handle.should.equal m1.handle.id
              links.id.content.should.equal m2.id
              done()

      s.register m2

    it 'should notify when model object change', (done) ->
      io.on 'register', (handle, type) ->
        # Register m3, do nothing
        io.off()
        io.on 'model:set', (handle, links) ->
          # Link m3, do nothing
          io.off()
          io.on 'model:set', (handle, links) ->
            # Test new m3 attrs
            links.should.not.have.property 'id'
            links.foo.content.should.equal m3.get 'foo'
            links.bar.content.should.equal m3.get 'bar'
            done()

      s.register m3
      m3.set 
        foo: 'Kha'
        bar: 123

    it 'should register and notify simple backbone collection', (done) ->
      # Order: Regiter c1, regiter m1, link m1, register m3, link m3, add c1, remove m3
      io.on 'register', (handleId1, type) ->
        handleId1.should.equal c1.handle.id
        # Register c1, do nothing
        io.off()
        io.on 'register', (handleId2, type) ->
          # Register m1, do nothing
          handleId2.should.equal m1.handle.id
          io.off()
          io.on 'register', (handleId3, type) ->
            # Register m3, do nothing
            handleId3.should  .equal m3.handle.id
            io.off()
            # Add c1
            io.on 'collection:add', (handleId4, els) ->
              handleId4.should.equal c1.handle.id
              els.should.eql [ m1.handle.id, m3.handle.id ]
              io.off()
              # Remove m3
              io.on 'collection:remove', (handleId5, elHandleId1) ->
                handleId5.should.equal c1.handle.id
                elHandleId1.should.equal m3.handle.id
                # Re-add m3, make sure not register again
                io.off()
                io.on 'register', (handleId6, type) ->
                  throw Error('Shoudl not be here')
                io.on 'collection:add', (handleId7, els) ->
                  handleId7.should.equal c1.handle.id
                  els.should.eql [ m3.handle.id ]
                  io.off()
                  # Add m2
                  io.on 'register', (handleId, type) ->
                    # Not register m1 again
                    handleId.should.not.equal m1.handle.id

                  io.on 'collection:reset', (handleId, els) ->
                    handleId.should.equal c1.handle.id
                    els.should.eql [ m2.handle.id ]
                    io.off()                      
                    done()

                  c1.reset [ m2 ]

                c1.add m3

              c1.remove m3

      s.register c1
         