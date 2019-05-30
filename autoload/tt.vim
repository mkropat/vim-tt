let s:plugin_dir = expand('<sfile>:p:h:h')

function! s:init()
  let s:starttime = -1
  let s:remaining = -1
  let s:status = ''
  let s:ondone = []

  if ! exists('g:tt_taskfile')
    let g:tt_taskfile = '~/tasks'
  endif

  if ! exists('g:tt_soundfile')
    let g:tt_soundfile = s:plugin_dir . '/' . 'bell.wav'
  endif

  if ! exists('g:tt_statefile')
    let g:tt_statefile = s:get_vimdir() . '/' . 'tt.state'
  endif

  call s:read_state()

  if exists('g:tt_use_defaults') && g:tt_use_defaults
    call s:use_defaults()
  endif

  call timer_start(1000, function('s:tick'), { 'repeat': -1 })
endfunction

function! tt#get_status()
  return s:status
endfunction

function! tt#set_status(status)
  call s:set_state(s:starttime, s:remaining, a:status, s:ondone)
endfunction

function! tt#clear_status()
  call s:set_state(s:starttime, s:remaining, '', s:ondone)
endfunction

function! tt#set_timer(duration)
  let l:was_running = tt#is_running() && tt#get_remaining() > 0
  call tt#pause_timer()
  call s:set_state(s:starttime, s:parse_duration(a:duration), s:status, s:ondone)
  if l:was_running
    call tt#start_timer()
  endif
endfunction

function! tt#start_timer()
  if tt#get_remaining() >= 0
    call s:set_state(localtime(), s:remaining, s:status, s:ondone)
  endif
endfunction

function! tt#is_running()
  return s:starttime >= 0
endfunction

function! tt#pause_timer()
  call s:set_state(-1, tt#get_remaining(), s:status, s:ondone)
endfunction

function! tt#toggle_timer()
  if tt#is_running()
    call tt#pause_timer()
  else
    call tt#start_timer()
  endif
endfunction

function! tt#clear_timer()
  call s:set_state(-1, -1, s:status, [])
endfunction

function! tt#when_done(...)
  call s:set_state(s:starttime, s:remaining, s:status, a:000)
endfunction

function! tt#get_remaining()
  if ! tt#is_running()
    return s:remaining
  endif

  let l:elapsed = localtime() - s:starttime
  let l:difference = s:remaining - l:elapsed
  return l:difference < 0 ? 0 : l:difference
endfunction

function! tt#get_remaining_formatted()
  let l:remaining = tt#get_remaining()
  if tt#is_running()
    return s:format_abbrev_duration(l:remaining)
  else
    return l:remaining < 0
      \? ''
      \: '[' . s:format_duration(l:remaining) . ']'
  endif
endfunction

function! tt#play_sound()
  let l:soundfile = expand(g:tt_soundfile)
  if ! filereadable(l:soundfile)
    return
  endif

  if executable('afplay')
    call system('afplay ' . shellescape(l:soundfile) . ' &')
  elseif executable('aplay')
    call system('aplay ' . shellescape(l:soundfile) . ' &')
  elseif has('win32') && has ('pythonx')
    pythonx import winsound
    execute 'pythonx' printf('winsound.PlaySound(r''%s'', winsound.SND_ASYNC | winsound.SND_FILENAME)', l:soundfile)
  endif
endfunction

function! tt#open_tasks()
  if ! exists('g:tt_taskfile') || g:tt_taskfile ==# ''
    throw 'You must set g:tt_taskfile before calling tt#open_tasks()'
  endif

  call s:switch_to_file(expand(g:tt_taskfile))
endfunction

function! s:format_duration(duration)
  let l:hours = a:duration / 60 / 60
  let l:minutes = a:duration / 60 % 60
  let l:seconds = a:duration % 60
  return printf('%02d:%02d:%02d', l:hours, l:minutes, l:seconds)
endfunction

function! s:format_abbrev_duration(duration)
  let l:hours = a:duration / 60 / 60
  let l:minutes = a:duration / 60 % 60
  let l:seconds = a:duration % 60

  if a:duration <= 60
    return printf('%d:%02d', l:minutes, l:seconds)
  elseif l:hours > 0
    let l:displayed_hours = l:hours
    if l:minutes > 0 || l:seconds > 0
      let l:displayed_hours += 1
    endif
    return printf('%dh', l:displayed_hours)
  else
    let l:displayed_minutes = l:minutes
    if l:seconds > 0
      let l:displayed_minutes += 1
    endif
    return printf('%dm', l:displayed_minutes)
  endif
endfunction

function! s:get_vimdir()
  return split(&runtimepath, ',')[0]
endfunction

function! s:parse_duration(duration)
  let l:hours = 0
  let l:minutes = 0
  let l:seconds = 0

  let l:parts = split(a:duration, ":")
  if len(l:parts) == 1
    let [l:minutes] = l:parts
  elseif len(l:parts) == 2
    let [l:minutes, l:seconds] = l:parts
  elseif len(parts) == 3
    let [l:hours, l:minutes, l:seconds] = l:parts
  endif

  return l:hours*60*60 + l:minutes*60 + l:seconds
endfunction

function! s:read_state()
  if filereadable(expand(g:tt_statefile))
    let l:state = readfile(expand(g:tt_statefile))
    if l:state[0] ==# 'tt.v1' && len(l:state) >= 4
      let s:starttime = l:state[1]
      let s:remaining = l:state[2]
      let s:status = l:state[3]
      let s:ondone = l:state[4:]
    endif
  endif
endfunction

function! s:set_state(starttime, remaining, status, ondone)
  let s:starttime = a:starttime
  let s:remaining = a:remaining
  let s:status = a:status
  let s:ondone = a:ondone

  let l:state = ['tt.v1', s:starttime, s:remaining, s:status]
  call extend(l:state, s:ondone)
  call writefile(l:state, expand(g:tt_statefile))
endfunction

function! s:switch_to_file(filename)
  let l:buf_id = bufnr(a:filename)

  let l:win_id = bufwinid(l:buf_id) " look in current tab
  if l:win_id >= 0
    call win_gotoid(l:win_id)
    return
  endif

  let l:win_ids = win_findbuf(l:buf_id) " look across all tabs
  if len(l:win_ids)
    call win_gotoid(l:win_ids[0])
    return
  endif

  execute 'vsplit' a:filename
endfunction

function! s:tick(timer)
  if len(s:ondone) && tt#is_running() && tt#get_remaining() == 0
    let l:ondone = s:ondone
    call s:set_state(s:starttime, s:remaining, s:status, [])
    execute join(l:ondone)
  endif

  doautocmd <nomodeline> User TtTick
endfunction

function! s:use_defaults()
  command! Work
    \  call tt#set_timer(25)
    \| call tt#start_timer()
    \| call tt#set_status('|working|')
    \| call tt#when_done('AfterWork')

  command! AfterWork
    \  call tt#play_sound()
    \| call tt#open_tasks()
    \| Break

  command! Break
    \  call tt#set_timer(5)
    \| call tt#start_timer()
    \| call tt#set_status('|break|')
    \| call tt#when_done('AfterBreak')

  command! AfterBreak
    \  call tt#play_sound()
    \| call tt#set_status('|ready|')
    \| call tt#clear_timer()

  command! ClearTimer
    \  call tt#clear_status()
    \| call tt#clear_timer()

  command! PauseTimer call tt#toggle_timer()
  command! OpenTasks call tt#open_tasks()

  nnoremap <Leader>tb :Break<cr>
  nnoremap <Leader>tp :PauseTimer<cr>
  nnoremap <Leader>tt :OpenTasks<cr>
  nnoremap <Leader>tw :Work<cr>
endfunction

call s:init()
