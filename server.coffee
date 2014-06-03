events = require 'events'
EventEmitter = events.EventEmitter
_ = require 'underscore'
backbone = require 'backbone'

# A sync use mainly by debugger
# Maybe extend for other collaborative activity
# Store all sync object, key by it cid? (depend on backbone model)
# Object on server has it own id and cid?
# All object are created ONLY on server!!!
# Determine object by path? REST inspire

# Object handle
class Handle
  constructor: (@id, @sync, @obj) ->
    @obj.handle = this

class Sync extends backbone.Model
  constructor: (@socket) ->
    super()
    # Handle to all managed objects
    @handles = {}
    @acceptMethods = {}
    @typeToName = {}
    @socket.on 's:invoke', @onInvoke

  # TODO: Becareful remote call harmful
  onInvoke: (handleId, method, args, callback) =>
    handle = @handles[handleId]
    if not handle
      callback 'Object not found'
    else
      obj = handle.obj
      clazz = obj.constructor
      type = @typeToName[clazz]
      # Accept only async methods
      if type and type.methods and type.methods.indexOf(method) != -1
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

  addTypeToName: (type, name, methods) ->
    @typeToName[type] = 
      name: name
      methods: methods

  # TODO: Add ad-hoc type
  getTypeName: (obj) ->
    # Try to get real type of object
    if @typeToName[obj.constructor]
      return @typeToName[obj.constructor].name
    if obj instanceof backbone.Model
      return 'backbone.Model'
    else if obj instanceof backbone.Collection
      return 'backbone.Collection'
    return null

  isRegistered: (obj) ->
    return obj.handle and obj.handle.id and @handles[obj.handle.id]

  linkAttributes: (handle, attrs) ->
    links = {}
    for name, attr of attrs
      attrHandle = @register attr
      if attrHandle instanceof Handle
        links[name] = 
          handle: attrHandle.id
      else  
        links[name] = 
          content: attrHandle
    @broadcast 's:model:set', handle.id, links

  linkCollection: (handle, els, isReset) ->
    links = []
    for e in els
      childHandle = @register e
      links.push childHandle.id
    if isReset
      @broadcast 's:collection:reset', handle.id, links
    else
      @broadcast 's:collection:add', handle.id, links
    
  # Add new tracking object
  # Each type should have ad-hoc factory
  register: (obj) ->
    # If object not a backbone object simply put it out
    # Root objects need to be a backbone to keep data sync
    type = @getTypeName obj
    # Primitive
    if type is null
      return obj

    # Already register
    if @isRegistered obj
      return obj.handle
    
    # From here: only managed register type
    # Create new handle
    # TODO: Becareful overflow id
    handle = new Handle _.uniqueId('sync'), this, obj
    # Add handle to tracking
    @handles[handle.id] = handle
    # Broadcast
    @broadcast 's:register', handle.id, type
      
    # Model
    if obj instanceof backbone.Model
      # Recursively and link
      obj.on 'change', ->
        # Re-link
        @linkAttributes handle, obj.changed
      , this
      # Link
      @linkAttributes handle, obj.toJSON()

    # Collection
    else if obj instanceof backbone.Collection
      # Bind event
      obj.on 'add', (el) ->
        # Simply add link
        @linkCollection handle, [el], false
      , this

      obj.on 'remove', (el) ->
        @broadcast 's:collection:remove', handle.id, el.handle.id
      , this

      obj.on 'reset', ->
        @linkCollection handle, obj.models, true
      , this

      @linkCollection handle, obj.models

      # TODO: Unbind event???
      
    return handle

  # Simply broadcast through event emitter
  broadcast: ->
    @socket.emit.apply @socket, arguments

  # What happen when new node join?
  # Get state
  #   - All handle and type
  #   - For each handle generate link

  # Free? singleton?
  free: ->
    # Fire event?
    # Clear all handles event
    for id, handle of @handles
      obj = handle.obj
      delete obj.handle
      # Off all events
      obj.off null, null, this
    # Free all handle
    @handles = null
    @socket.on 's:invoke', @onInvoke

exports.Sync = Sync
