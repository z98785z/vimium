
# The important data structure here is the "keyState".  The key state is a non-empty list of objects, the keys
# of which are key names, and the values are other key-mapping objects or commands (strings).  Key-mapping
# objects can be arbitrarily nested; so we support any length of multi-key mapping.
#
# Whenever we consume a key, we append a new copy of the global key mapping to the key state (hence, the
# global mappings are always available, and the key state is always non-empty).

class KeyHandlerMode extends Mode
  useCount: true
  countPrefix: 0
  keydownEvents: {}
  keyState: []

  constructor: (options) ->
    # A function accepting a command name and a count; required.
    @commandHandler = options.commandHandler ? (->)
    # A Key mapping structure; required.
    @keyMapping = options.keyMapping ? {}
    @useCount = false if options.noCount
    @reset()

    # We don't pass these options on to super().
    options = Utils.copyObjectOmittingProperties options, "commandHandler", "keyMapping", "noCount"

    super extend options,
      keydown: @onKeydown.bind this
      keypress: @onKeypress.bind this
      keyup: @onKeyup.bind this
      # We cannot track matching keydown/keyup events if we lose the focus.
      blur: (event) => @alwaysContinueBubbling =>
        @keydownEvents = {} if event.target == window

  onKeydown: (event) ->
    keyChar = KeyboardUtils.getKeyCharString event

    if KeyboardUtils.isEscape event
      if @isInResetState()
        @continueBubbling
      else
        @reset()
        DomUtils.suppressKeyupAfterEscape handlerStack
        false # Suppress event.

    else if keyChar and @keyCharIsKeyStatePrefix keyChar
        @advanceKeyState keyChar
        commands = @keyState.filter (entry) -> "string" == typeof entry
        @invokeCommand commands[0] if 0 < commands.length
        false # Suppress event.

    else
      # We did not handle the event, but we might handle the subsequent keypress event.  If we *will* be
      # handling that event, then we need to suppress propagation of this keydown event to prevent triggering
      # page features like Google instant search.
      keyChar = KeyboardUtils.getKeyChar event
      if keyChar and (@keyCharIsKeyStatePrefix(keyChar) or @isCountKey keyChar)
        DomUtils.suppressPropagation event
        @keydownEvents[@getEventCode event] = true
        @stopBubblingAndTrue
      else
        @countPrefix = 0 if keyChar
        @continueBubbling

  onKeypress: (event) ->
    keyChar = KeyboardUtils.getKeyCharString event
    if keyChar and @keyCharIsKeyStatePrefix keyChar
      @advanceKeyState keyChar
      commands = @keyState.filter (entry) -> "string" == typeof entry
      @invokeCommand commands[0] if 0 < commands.length
      false # Suppress event.
    else if keyChar and @isCountKey keyChar
      @countPrefix = @countPrefix * 10 + parseInt keyChar
      false # Suppress event.
    else
      @continueBubbling

  onKeyup: (event) ->
    eventCode = @getEventCode event
    if eventCode of @keydownEvents
      delete @keydownEvents[eventCode]
      DomUtils.suppressPropagation event
      @stopBubblingAndTrue
    else
      @continueBubbling

  # This tests whether keyChar is a prefix of any current mapping in the key state.
  keyCharIsKeyStatePrefix: (keyChar) ->
    for mapping in @keyState
      return true if keyChar of mapping
    false

  # This is called whenever a keyChar is matched.  We keep any existing entries matching keyChar, and append a
  # new copy of the global key mappings.
  advanceKeyState: (keyChar) ->
    newKeyState =
      for mapping in @keyState
        continue unless keyChar of mapping
        mapping[keyChar]
    @keyState = [newKeyState..., @keyMapping]

  # This is called to invoke a command and reset the key state.
  invokeCommand: (command) ->
    countPrefix = if 0 < @countPrefix then @countPrefix else 1
    @reset()
    @commandHandler command, countPrefix

  # Reset the state (as if no keys had been handled).
  reset: ->
    @countPrefix = 0
    @keyState = [@keyMapping]

  # This tests whether we are in the reset state.  It is used to check whether we should be using escape to
  # reset the key state, or passing it to the page.
  isInResetState: ->
    @countPrefix == 0 and @keyState.length == 1

  # This tests whether keyChar should be treated as a count key.
  isCountKey: (keyChar) ->
    return false unless @useCount and keyChar.length == 1
    if 0 < @countPrefix
      '0' <= keyChar <= '9'
    else
      '1' <= keyChar <= '9'

  getEventCode: (event) -> event.keyCode

# Demo/test code.
# A (very) poor-man's normal mode.

demoKeyMapping =
  j: "scrollDown"
  k: "scrollUp"
  i: "enterInsertMode"
  g:
    g: "scrollToTop"
    a: "scrollToTop"
    z: "scrollToBottom"
    i: "focusInput"
  # A three-key binding.
  a:
    b:
      c: "enterInsertMode"
      # And this should override "j" on its own.
      j: "enterInsertMode"

demoCommandHandler = (command, count) ->
  switch command
    when "scrollDown" then scrollDown()
    when "scrollUp" then scrollUp()
    when "scrollToTop" then scrollToTop count
    when "scrollToBottom" then scrollToBottom()
    when "enterInsertMode" then enterInsertMode()
    when "focusInput" then focusInput count

root = exports ? window
root.KeyHandlerMode = KeyHandlerMode
root.demoKeyMapping = demoKeyMapping
root.demoCommandHandler = demoCommandHandler
