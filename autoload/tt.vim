let s:plugin_dir = expand('<sfile>:p:h:h')

function! s:init()
  let s:state = {
    \'starttime': -1,
    \'remaining': -1,
    \'status': '',
    \'task_line': '',
    \'task_line_num': 0,
    \'ondone': ''
  \}
  let s:user_state = {}

  if ! exists('g:tt_taskfile')
    let g:tt_taskfile = '~/tasks'
  endif

  if ! exists('g:tt_soundfile')
    let g:tt_soundfile = s:plugin_dir . '/' . 'bell.wav'
  endif

  if ! exists('g:tt_statefile')
    let g:tt_statefile = s:get_vimdir() . '/' . 'tt.state'
  endif

  if ! exists('g:tt_progressmark')
    let g:tt_progressmark = '†'
  endif

  call s:read_state()

  if exists('g:tt_use_defaults') && g:tt_use_defaults
    call s:use_defaults()
  endif

  call timer_start(1000, function('s:tick'), { 'repeat': -1 })
endfunction

function! tt#get_status()
  return s:state.status
endfunction

function! tt#get_status_formatted()
  if s:state.status ==# ''
    return s:state.status
  endif
  return '|' . s:state.status . '|'
endfunction

function! tt#set_status(status)
  call s:set_state({ 'status': a:status }, {})
endfunction

function! tt#clear_status()
  call s:set_state({ 'status': '' }, {})
endfunction

function! tt#get_task()
  return s:format_task(s:state.task_line)
endfunction

function! tt#set_task(line_text, ...)
  let l:line_num = a:0 == 0 ? 0 : a:1
  call s:set_state({ 'task_line': a:line_text, 'task_line_num': l:line_num }, {})
endfunction

function! tt#clear_task()
  call s:set_state({ 'task_line': '' }, {})
endfunction

function! tt#set_timer(duration)
  let l:was_running = tt#is_running() && tt#get_remaining() > 0
  call tt#pause_timer()
  call s:set_state({ 'remaining': s:parse_duration(a:duration) }, {})
  if l:was_running
    call tt#start_timer()
  endif
endfunction

function! tt#start_timer()
  if tt#get_remaining() >= 0
    call s:set_state({ 'starttime': localtime() }, {})
  endif
endfunction

function! tt#is_running()
  return s:state.starttime >= 0
endfunction

function! tt#pause_timer()
  call s:set_state({ 'starttime': -1, 'remaining': tt#get_remaining() }, {})
endfunction

function! tt#toggle_timer()
  if tt#is_running()
    call tt#pause_timer()
  else
    call tt#start_timer()
  endif
endfunction

function! tt#clear_timer()
  call s:set_state({ 'starttime': -1, 'remaining': -1, 'ondone': '' }, {})
endfunction

function! tt#when_done(ondone)
  call s:set_state({ 'ondone': a:ondone }, {})
endfunction

function! tt#get_remaining()
  if ! tt#is_running()
    return s:state.remaining
  endif

  let l:elapsed = localtime() - s:state.starttime
  let l:difference = s:state.remaining - l:elapsed
  return l:difference < 0 ? 0 : l:difference
endfunction

function! tt#get_remaining_full_format()
  let l:remaining = tt#get_remaining()
  return s:format_duration_display(l:remaining)
endfunction

function! tt#get_remaining_smart_format()
  let l:remaining = tt#get_remaining()
  if tt#is_running()
    return s:format_abbrev_duration(l:remaining)
  else
    return l:remaining < 0
      \? ''
      \: s:format_duration_display(l:remaining)
  endif
endfunction

function! tt#get_state(key, default)
  return has_key(s:user_state, a:key)
    \? s:user_state[a:key]
    \: a:default
endfunction

function! tt#set_state(key, value)
  let l:user_state = {}
  let l:user_state[a:key] = a:value
  call s:set_state({}, l:user_state)
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

  let l:taskfile = expand(g:tt_taskfile)
  if bufwinid(l:taskfile) >= 0
    return
  endif

  let l:original_win = bufwinid('%')
  call s:open_file(l:taskfile)
  if ! exists('b:tt_taskfile_initialized')
    nnoremap <buffer> <CR> :WorkOnTask<CR>
    let b:tt_taskfile_initialized = 1
  endif
  call win_gotoid(l:original_win)
endfunction

function! tt#focus_tasks()
  let l:win_id = bufwinid(expand(g:tt_taskfile))

  if l:win_id < 0
    throw 'You must call tt#open_tasks() before calling tt#focus_tasks()'
  endif

  call win_gotoid(l:win_id)
endfunction

function! tt#can_be_task(line_text)
  return s:translate_to_task_matcher(a:line_text) !=# ''
endfunction

function! tt#mark_last_task()
  if s:state.task_line ==# '' || s:state.task_line_num == 0
    return
  endif

  let l:taskfile = expand(g:tt_taskfile)
  let l:task_win = bufwinid(l:taskfile)
  if l:task_win < 0
    throw 'You must call tt#open_tasks() before calling tt#mark_last_task()'
  endif

  let l:original_win = bufwinid('%')
  call win_gotoid(l:task_win)

  let l:line_num = s:find_matching_line()
  if l:line_num == 0
    echohl WarningMsg | echo "Unable to find task: " . s:format_task(s:state.task_line) | echohl None
  else
    call s:mark_task(l:line_num, l:line_num)
  endif

  call win_gotoid(l:original_win)
endfunction

function! tt#mark_task() range
  if bufnr(expand(g:tt_taskfile)) !=# bufnr('%')
    throw 'You must call tt#open_tasks() before calling tt#mark_task()'
  endif

  call s:mark_task(a:firstline, a:lastline)
endfunction

function! s:mark_task(first, last)
  let l:orig_modified = &modified

  for l:line_num in range(a:first, a:last)
    if tt#can_be_task(getline(l:line_num))
      call s:append_progressmark(l:line_num)
    endif
  endfor

  if ! l:orig_modified
    write
  endif
endfunction

function! s:find_matching_line()
  let l:target = s:translate_to_task_matcher(s:state.task_line)

  let l:top = s:state.task_line_num
  let l:bottom = l:top + 1

  while l:top > 0 || l:bottom <= line('$')
    if l:top > 0
      if s:translate_to_task_matcher(getline(l:top)) ==? l:target
        return l:top
      endif
      let l:top -= 1
    endif

    if l:bottom <= line('$')
      if s:translate_to_task_matcher(getline(l:bottom)) ==? l:target
        return l:bottom
      endif
      let l:bottom += 1
    endif
  endwhile

  return 0
endfunction

function! s:format_task(line)
  let l:result = a:line
  let l:result = substitute(l:result, '^\s*\%(\W\+\s\+\)\?\(.\{-}\)\%(\s\+\W\+\)\?\W*$', '\1', '')
  let l:result = substitute(l:result, '\s\+', ' ', 'g')
  return l:result
endfunction

function! s:translate_to_task_matcher(line)
  return s:trim(substitute(a:line, '\W\+', ' ', 'g'))
endfunction

function! s:append_progressmark(line_num)
  let l:line = getline(a:line_num)
  if strcharpart(l:line, strchars(l:line) - 1, 1) ==# g:tt_progressmark
    call setline(a:line_num, l:line . g:tt_progressmark)
  else
    call setline(a:line_num, l:line . " " . g:tt_progressmark)
  endif
endfunction

function! s:trim(str)
  return substitute(a:str, '^\s*\(.\{-}\)\s*$', '\1', '')
endfunction

function! s:format_duration_display(duration)
  return '[' . s:format_duration(a:duration) . ']'
endfunction

function! s:format_duration(duration)
  let l:duration = a:duration < 0 ? 0 : a:duration
  let l:hours = l:duration / 60 / 60
  let l:minutes = l:duration / 60 % 60
  let l:seconds = l:duration % 60
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
    if l:state[0] ==# 'tt.v4' && len(l:state) == 3
      let s:state = eval(l:state[1])
      let s:user_state = eval(l:state[2])
    endif
  endif
endfunction

function! s:set_state(script_state, user_state)
  for l:key in keys(a:script_state)
    let s:state[l:key] = a:script_state[l:key]
  endfor

  for l:key in keys(a:user_state)
    let s:user_state[l:key] = a:user_state[l:key]
  endfor

  let l:state = ['tt.v4', string(s:state), string(s:user_state)]
  call writefile(l:state, expand(g:tt_statefile))
endfunction

function! s:open_file(filename)
  if s:is_new_buffer()
    execute 'edit' a:filename
  else
    execute 'botright' 'vsplit' a:filename
  endif
endfunction

function! s:is_new_buffer()
  let l:is_unnamed = bufname('%') == ''
  let l:is_empty = line('$') == 1 && getline(1) == ''
  let l:is_normal = &buftype == ''
  return l:is_unnamed && l:is_empty && l:is_normal
endfunction

function! s:tick(timer)
  if s:state.ondone !=# '' && tt#is_running() && tt#get_remaining() == 0
    let l:ondone = s:state.ondone
    call s:set_state({ 'ondone': '' }, {})
    execute l:ondone
  endif

  doautocmd <nomodeline> User TtTick
endfunction

function! s:use_defaults()
  command! Work
    \  call tt#set_timer(25)
    \| call tt#start_timer()
    \| call tt#set_status('working')
    \| call tt#when_done('AfterWork')

  command! AfterWork
    \  call tt#play_sound()
    \| call tt#open_tasks()
    \| Break

  command! WorkOnTask
    \  if tt#can_be_task(getline('.'))
    \|   call tt#set_task(getline('.'), line('.'))
    \|   execute 'Work'
    \|   echomsg "Current task: " . tt#get_task()
    \|   call tt#when_done('AfterWorkOnTask')
    \| endif

  command! AfterWorkOnTask
    \  call tt#play_sound()
    \| call tt#open_tasks()
    \| call tt#mark_last_task()
    \| Break

  command! Break call Break()
  function! Break()
    let l:count = tt#get_state('break-count', 0)
    if l:count >= 3
      call tt#set_timer(15)
      call tt#set_status('long break')
      call tt#set_state('break-count', 0)
    else
      call tt#set_timer(5)
      call tt#set_status('break')
      call tt#set_state('break-count', l:count + 1)
    endif
    call tt#start_timer()
    call tt#clear_task()
    call tt#when_done('AfterBreak')
  endfunction

  command! AfterBreak
    \  call tt#play_sound()
    \| call tt#set_status('ready')
    \| call tt#clear_timer()

  command! ClearTimer
    \  call tt#clear_status()
    \| call tt#clear_task()
    \| call tt#clear_timer()

  command! -range MarkTask <line1>,<line2>call tt#mark_task()
  command! OpenTasks call tt#open_tasks() <Bar> call tt#focus_tasks()
  command! -nargs=1 SetTimer call tt#set_timer(<f-args>)
  command! ShowTimer echomsg tt#get_remaining_full_format() . " " . tt#get_status_formatted() . " " . tt#get_task()
  command! ToggleTimer call tt#toggle_timer()

  nnoremap <Leader>tb :Break<cr>
  nnoremap <Leader>tm :MarkTask<cr>
  xnoremap <Leader>tm :MarkTask<cr>
  nnoremap <Leader>tp :ToggleTimer<cr>
  nnoremap <Leader>ts :ShowTimer<cr>
  nnoremap <Leader>tt :OpenTasks<cr>
  nnoremap <Leader>tw :Work<cr>
endfunction

call s:init()
