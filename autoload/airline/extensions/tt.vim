scriptencoding utf-8

if exists('g:loaded_tt_airline')
  finish
else
  let g:loaded_tt_airline = 'yes'
endif

let s:spc = g:airline_symbols.space

function! airline#extensions#tt#init(ext)
  call airline#parts#define_raw('tt', '%{airline#extensions#tt#get()}')

  call a:ext.add_statusline_func('airline#extensions#tt#apply')
endfunction

function! airline#extensions#tt#apply(...)
  let w:airline_section_c = get(w:, 'airline_section_c', g:airline_section_c)
  let w:airline_section_c .= s:spc.g:airline_left_alt_sep.s:spc.'%{airline#extensions#tt#get()}'
endfunction

function! airline#extensions#tt#get()
  let parts = []

  let remaining = tt#get_remaining_smart_format()
  if remaining !=# ''
    call add(parts, remaining)
  endif

  let status = tt#get_status_formatted()
  if status !=# ''
    call add(parts, status)
  endif

  return join(parts, ' ')
endfunction

augroup TtAirline
  autocmd!
  autocmd User TtTick call airline#update_statusline()
augroup END
