events = require 'events'
EventEmitter = events.EventEmitter
_ = require 'underscore'
backbone = require 'backbone'

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
    @sync.socket.emit.call @sync.socket, 's:invoke', @id, method, args, callback

class Sync extends backbone.Model
  constructor: (@socket) ->
    super()
    @handles = {}
    @socket.on 's:register', @onRegister
    @socket.on 's:model:set', @onModelSet
    @socket.on 's:collection:add', @onCollectionAdd
    @socket.on 's:collection:remove', @onCollectionRemove
    @socket.on 's:collection:reset', (handleId, els) =>
      @onCollectionAdd handleId, els, true

    # Default types
    @nameToType = 
      'backbone.Model': backbone.Model
      'backbone.Collection': backbone.Collection

  addNameToType: (name, type) ->
    @nameToType[name] = type

  getType: (name) ->
    if @nameToType[name]
      return @nameToType[name]

  onCollectionRemove: (handleId, childHandleId) =>
    obj = @getObjectByHandleId handleId
    child = @getObjectByHandleId childHandleId
    obj.remove child

  onCollectionAdd: (handleId, els, isReset) =>
    obj = @getObjectByHandleId handleId
    children = []
    for el in els
      child = @getObjectByHandleId el
      children.push child
    if isReset
      obj.reset children
    else
      obj.add children

  onModelSet: (handleId, links) =>
    obj = @getObjectByHandleId handleId
    for key, value of links
      # Handle id
      if value.handle
        child = @getObjectByHandleId value.handle
        obj.set key, child
      if value.content
        obj.set key, value.content

  getObjectByHandleId: (handleId) ->
    return @handles[handleId].obj

  onRegister: (handleId, type) =>
    if @handles[handleId]
      throw Error('Already registered')

    clazz = @getType type
    if not clazz
      throw Error('Type ' + type + 'was not registered')
    obj = new clazz()

    handle = new Handle handleId, this, obj
    @handles[handleId] = handle

exports.Sync = Sync