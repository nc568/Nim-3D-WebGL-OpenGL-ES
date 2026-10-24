## Minimal Linux SDL2 GLES window host. One event consumer on the main thread.
## Explicit cleanup; dispose GPU resources BEFORE close while this context is current.
when defined(js) or not defined(linux):
  {.error: "This SDL2 host currently targets native Linux only".}
const sdlLibrary {.strdefine.} = "libSDL2-2.0.so.0"
{.push cdecl, dynlib:sdlLibrary.}
proc SDL_InitSubSystem(flags: uint32): cint {.importc.}
proc SDL_QuitSubSystem(flags: uint32) {.importc.}
proc SDL_GetError(): cstring {.importc.}
proc SDL_GL_SetAttribute(attr,value: cint): cint {.importc.}
proc SDL_CreateWindow(title: cstring; x,y,w,h: cint; flags: uint32): pointer {.importc.}
proc SDL_DestroyWindow(window: pointer) {.importc.}
proc SDL_GL_CreateContext(window: pointer): pointer {.importc.}
proc SDL_GL_DeleteContext(context: pointer) {.importc.}
proc SDL_GL_MakeCurrent(window,context: pointer): cint {.importc.}
proc SDL_GL_GetAttribute(attr: cint; value: ptr cint): cint {.importc.}
proc SDL_GL_SetSwapInterval(interval: cint): cint {.importc.}
proc SDL_GL_GetDrawableSize(window: pointer; w,h: ptr cint) {.importc.}
proc SDL_GL_SwapWindow(window: pointer) {.importc.}
proc SDL_GL_GetProcAddress*(name: cstring): pointer {.importc.}
proc SDL_GetWindowFlags(window: pointer): uint32 {.importc.}
proc SDL_SetWindowSize(window: pointer; w,h: cint) {.importc.}
proc SDL_HideWindow(window: pointer) {.importc.}
proc SDL_ShowWindow(window: pointer) {.importc.}
proc SDL_PollEvent(event: pointer): cint {.importc.}
proc SDL_PushEvent(event: pointer): cint {.importc.}
proc SDL_GetKeyboardState(count: ptr cint): ptr UncheckedArray[uint8] {.importc.}
proc SDL_GetPerformanceCounter(): uint64 {.importc.}
proc SDL_GetPerformanceFrequency(): uint64 {.importc.}
proc SDL_Delay(ms: uint32) {.importc.}
{.pop.}

type
  SdlWindow* = ref object
    window, context: pointer
    alive: bool
  WindowInput* = object
    quit*: bool
    orbit*, zoom*: int

proc failure(action: string): ref IOError =
  newException(IOError,action & ": " & $SDL_GetError())
proc requireWindow(host: SdlWindow) =
  if host.isNil or not host.alive: raise newException(ValueError,"Window is closed")
proc makeCurrent*(host: SdlWindow) =
  host.requireWindow()
  if SDL_GL_MakeCurrent(host.window,host.context) != 0: raise failure("makeCurrent")
proc close*(host: SdlWindow) =
  if host.isNil or not host.alive: return
  host.alive = false
  SDL_GL_DeleteContext(host.context)
  SDL_DestroyWindow(host.window)
  SDL_QuitSubSystem(0x20)
proc openWindow*(version = 3; width = 800; height = 600): SdlWindow =
  if version notin [2,3] or width < 1 or height < 1 or width > 8192 or height > 8192:
    raise newException(ValueError,"Invalid GLES version/window dimensions")
  if SDL_InitSubSystem(0x20) != 0: raise failure("SDL video init")
  new(result)
  try:
    for setting in [(21,4),(17,version),(18,0),(5,1),(6,24),(0,8),(1,8),(2,8)]:
      if SDL_GL_SetAttribute(cint(setting[0]),cint(setting[1])) != 0:
        raise failure("SDL GLES attribute")
    result.window = SDL_CreateWindow("Nim GLES - arrows orbit, W/S zoom, Esc quit",
      0x2FFF0000,0x2FFF0000,cint(width),cint(height),0x00000002'u32 or 0x20 or 0x2000)
    if result.window == nil: raise failure("SDL window creation")
    result.context = SDL_GL_CreateContext(result.window)
    if result.context == nil: raise failure("SDL GLES context creation")
    result.alive = true
    result.makeCurrent()
    var profile, major: cint
    if SDL_GL_GetAttribute(21,addr profile) != 0 or SDL_GL_GetAttribute(17,addr major) != 0 or
        profile != 4 or major < cint(version):
      raise newException(IOError,"SDL did not provide the requested GLES profile")
    discard SDL_GL_SetSwapInterval(1) # driver may not support vsync
  except:
    if result.context != nil: SDL_GL_DeleteContext(result.context)
    if result.window != nil: SDL_DestroyWindow(result.window)
    result.alive = false
    SDL_QuitSubSystem(0x20)
    raise
proc drawableSize*(host: SdlWindow): tuple[width,height:int] =
  host.requireWindow()
  var w,h: cint
  SDL_GL_GetDrawableSize(host.window,addr w,addr h)
  (int(w),int(h))
proc suspended*(host: SdlWindow): bool =
  host.requireWindow()
  (SDL_GetWindowFlags(host.window) and (0x8'u32 or 0x40)) != 0
proc resize*(host: SdlWindow; width,height: int) =
  host.requireWindow()
  if width < 1 or height < 1 or width > 8192 or height > 8192:
    raise newException(ValueError,"Invalid window dimensions")
  SDL_SetWindowSize(host.window,cint(width),cint(height))
proc setHidden*(host: SdlWindow; hidden: bool) =
  host.requireWindow()
  if hidden: SDL_HideWindow(host.window)
  else: SDL_ShowWindow(host.window)
proc swap*(host: SdlWindow) =
  host.requireWindow()
  SDL_GL_SwapWindow(host.window)
proc poll*(host: SdlWindow): WindowInput =
  host.requireWindow()
  # SDL2 event union is 56 bytes on supported 64-bit Linux ABIs. Reserve 64,
  # naturally uint64-aligned; read only public SDL2 event header/close fields.
  var event: array[8,uint64]
  while SDL_PollEvent(addr event[0]) != 0:
    let kind = cast[ptr uint32](addr event[0])[]
    if kind == 0x100 or (kind == 0x200 and cast[ptr UncheckedArray[uint8]](addr event[0])[12] == 14):
      result.quit = true
  var count: cint
  let keys = SDL_GetKeyboardState(addr count)
  if keys != nil and count > 80:
    result.quit = result.quit or keys[41] != 0
    result.orbit = int(keys[79] != 0)-int(keys[80] != 0)
    result.zoom = int(keys[22] != 0)-int(keys[26] != 0)
proc requestQuit*(host: SdlWindow) =
  ## Integration-test/host hook: goes through the real SDL event queue.
  host.requireWindow()
  var event: array[8,uint64]
  cast[ptr uint32](addr event[0])[] = 0x100
  if SDL_PushEvent(addr event[0]) != 1: raise failure("SDL quit event")
proc seconds*(): float64 = float64(SDL_GetPerformanceCounter())/float64(SDL_GetPerformanceFrequency())
proc idle*(ms = 10'u32) = SDL_Delay(ms)
