loadModule = (_, backbone) ->
  exports = {}

  class Handle
    constructor: (@id, @sync, @obj) ->
      @obj.handle = this

    # method, arg0..., callback
    # restrict single callback because of socket.io
    invoke: (method) ->
      args =  Array.prototype.slice.call arguments
      # If last argument is a function
      if _.isFunction(_.last(args))
        callback = args.pop()
      method = args.shift()
      # Optimize socket.io
      @sync.channel.trigger.call @sync.channel, 'invoke', @id, method, args, callback

    # State => something internal
    loadState: (state) ->
      # Do nothing

  class ModelHandle extends Handle
    @className: 'backbone.Model'

    @clazz: backbone.Model

    @bindEvents: (sync) ->
      sync.channel.on 'model:set', (handleId, links) ->
        obj = sync.getObjectByHandleId handleId
        obj.handle.loadState links

    constructor: (id, sync, obj) ->
      super id, sync, obj

    # State => attributes
    loadState: (links) ->
      for key, value of links
        # Handle id
        if value.handle
          child = @sync.getObjectByHandleId value.handle
          @obj.set key, child
        if value.content
          @obj.set key, value.content 

  class CollectionHandle extends Handle
    @className: 'backbone.Collection'

    @clazz: backbone.Collection

    @bindEvents: (sync) ->
      onCollectionRemove = (handleId, childHandleId) ->
        obj = sync.getObjectByHandleId handleId
        child = sync.getObjectByHandleId childHandleId
        obj.remove child

      onCollectionAdd = (handleId, els, isReset) ->
        obj = sync.getObjectByHandleId handleId
        obj.handle.loadState els, isReset

      sync.channel.on 'collection:add', onCollectionAdd
      sync.channel.on 'collection:remove', onCollectionRemove
      sync.channel.on 'collection:reset', (handleId, els) ->
        onCollectionAdd handleId, els, true

    constructor: (id, sync, obj) ->
      super id, sync, obj

    # State => elemements
    loadState: (els, isReset) ->
      children = []
      for el in els
        child = @sync.getObjectByHandleId el
        children.push child
      if isReset
        @obj.reset children
      else
        @obj.add children

  class Sync extends backbone.Model
    # Makesure load state before event? Race condition???
    constructor: (@channel) ->
      super()
      @handles = {}
      @channel.on 'register', @onRegister
      @channel.on 'free', @onFree
      
      # Default types
      @types = {}
      @addType ModelHandle
      @addType CollectionHandle

    addType: (type) ->
      @types[type.className] = type
      # Bind event
      type.bindEvents this

    getType: (name) -> @types[name]    

    getObjectByHandleId: (handleId) ->
      return @handles[handleId].obj

    onRegister: (handleId, type) =>
      if @handles[handleId]
        throw Error('Already registered')

      HandleType = @getType type
      if not HandleType
        throw Error('Type ' + type + 'was not registered')
      obj = new HandleType.clazz()

      handle = new HandleType handleId, this, obj
      @handles[handleId] = handle

    onFree: =>
      @trigger 'free'

    loadState: (state) ->
      # Register object
      for o in state
        @onRegister o.id, o.type
      # Init state
      for o in state
        obj = @getObjectByHandleId o.id
        obj.handle.loadState o.state

  exports.Sync = Sync
  exports.Handle = Handle
  exports.CollectionHandle = CollectionHandle
  exports.ModelHandle = ModelHandle
  exports

# Unify module for commonjs and amd
if typeof module isnt 'undefined'
  # Commondjs
  module.exports = loadModule require('underscore'), require('backbone')
else if typeof define is 'function'
  # AMD
  define [ 'underscore', 'backbone' ], loadModule