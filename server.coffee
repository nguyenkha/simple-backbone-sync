_ = require 'underscore'
backbone = require 'backbone'

# A sync use mainly by debugger
# Maybe extend for other collaborative activity
# Store all sync object, key by it cid? (depend on backbone model)
# Object on server has it own id and cid?
# All object are created ONLY on server!!! => Master-Slave
# Determine object by path? REST inspire

# Object handle
class Handle
  constructor: (@id, @sync, @obj) ->
    @obj.handle = this
    # Invoke

  register: ->
    # Do nothing

  getState: ->
    # Do nothing

  free: ->
    # Free handle link
    delete @obj.handle
    # Off all events
    @obj.off null, null, this

class ModelHandle extends Handle
  @clazz: backbone.Model
  
  @className: 'backbone.Model'

  constructor: (id, sync, obj) ->
    super id, sync, obj

  register: ->
    @obj.on 'change', ->
      @linkAttributes @obj.changed
    , this
    @linkAttributes @obj.attributes

  linkAttributes: (attrs) ->
    @sync.broadcast 'model:set', @id, @getState(attrs)

  getState: (attrs) ->
    if not attrs
      attrs = @obj.attributes
    links = {}
    for name, attr of attrs
      attrHandle = @sync.register attr
      if attrHandle instanceof Handle
        links[name] = 
          handle: attrHandle.id
      else  
        links[name] = 
          content: attrHandle
    return links

class CollectionHandle extends Handle
  @clazz: backbone.Collection
  
  @className: 'backbone.Collection'

  constructor: (id, sync, obj) ->
    super id, sync, obj

  register: ->
    @obj.on 'add', (el) ->
      # Simply add link
      @linkCollection [el], false
    , this

    @obj.on 'remove', (el) ->
      @sync.broadcast 'collection:remove', @id, el.handle.id
    , this

    @obj.on 'reset', ->
      @linkCollection @obj.models, true
    , this

    @linkCollection @obj.models

  linkCollection: (els, isReset) ->
    links = @getState els
    if isReset
      @sync.broadcast 'collection:reset', @id, links
    else
      @sync.broadcast 'collection:add', @id, links

  getState: (els) ->
    if not els
      els = @obj.models
    links = []
    for e in els
      childHandle = @sync.register e
      links.push childHandle.id
    return links

class Sync extends backbone.Model
  constructor: (@channel) ->
    super()
    # Handle to all managed objects
    @handles = {}
    @types = []
    @channel.on 'invoke', @onInvoke

  # Default true
  canInvoke: (handle, type, method, args) -> true

  # TODO: Becareful remote call harmful
  onInvoke: (handleId, method, args, callback) =>
    handle = @handles[handleId]
    if not handle
      callback 'Object not found'
    else
      obj = handle.obj
      type = @getType obj
      # Accept only async methods
      if type and type.methods and type.methods.indexOf(method) != -1 and @canInvoke(handle, type, method, args)
        try 
          args.push callback
          # Async
          obj[method].apply obj, args
        catch e
          # Callback on exception
          callback e.toString()

      else
        # Not throw real error
        callback 'Method not found'

  getType: (obj) -> 
    type = _.find @types, (el) -> 
      el.clazz is obj.constructor
    # Fallback backbone base
    if not type
      if obj instanceof ModelHandle.clazz
        type = ModelHandle
      else if obj instanceof CollectionHandle.clazz
        type = CollectionHandle
    return type

  addType: (type) ->
    @types.push type

  isRegistered: (obj) ->
    return obj.handle and obj.handle.id and @handles[obj.handle.id]
    
  # Add new tracking object
  # Each type should have ad-hoc factory
  register: (obj) ->
    # If object not a backbone object simply put it out
    # Root objects need to be a backbone to keep data sync
    type = @getType obj
    # Primitive, just return as it is
    if not type
      return obj

    # Already register
    if @isRegistered obj
      return obj.handle

    # From here: only managed register type
    # Create new handle
    # TODO: Becareful overflow id
    handle = new type _.uniqueId('sync'), this, obj
    # Add handle to tracking
    @handles[handle.id] = handle
    # Broadcast
    @broadcast 'register', handle.id, type.className

    # Self register
    handle.register()
      
    return handle

  # Simply broadcast through event emitter
  broadcast: ->
    @channel.trigger.apply @channel, arguments

  # What happen when new node join?
  # Get state
  #   - All handle and type
  #   - For each handle generate link
  getState: ->
    result = []
    for key, handle of @handles
      result.push
        id: key
        type: handle.constructor.className
        state: handle.getState()
    return result

  # Free? singleton?
  free: ->
    # Fire event?
    # Clear all handles event
    for id, handle of @handles
      handle.free()
    # Free all handle
    @handles = null
    @channel.off 'invoke', @onInvoke
    # Free event
    @trigger 'free'
    @broadcast 'free'

exports.Sync = Sync
exports.Handle = Handle
exports.CollectionHandle = CollectionHandle
exports.ModelHandle = ModelHandle