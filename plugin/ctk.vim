" ==========================================================
" Script Name:  code toolkit
" File Name:    ctk.vim
" Author:       StarWing
" Version:      0.1
" Last Change:  2009-02-10 22:28:49
" Must After Vim 7.0 {{{1

if exists('loaded_ctk')
    finish
endif
let loaded_ctk = 'v0.1'

if v:version < 700
    echomsg "ctk.vim requires Vim 7.0 or above."
    finish
endif

" :%s/^\s*\zsCTKtrace/" &/g
" :%s/" \zsCTKtrace/&/g " restore traces
" map <m-r> :exec '!start '.expand('%:p:h:h').'/run.cmd'<CR>
" let s:debug = 1
let old_cpo = &cpo
set cpo&vim

" }}}1
" ==========================================================
" Options {{{1

" hotkeys {{{2
" $num, $id

if !exists('ctk_compile_hotkey')
    let ctk_compile_hotkey = '\c$id'
endif

if !exists('ctk_run_hotkey')
    let ctk_run_hotkey = '<m-$num>'
endif

" }}}2
" auto_generate_name {{{2

if !exists('ctk_temp_folder')
    let ctk_temp_folder = './noname'
endif

if !exists('ctk_auto_generated_fname')
    let ctk_auto_generated_fname = 'strftime("%Y-%m-%d")."-".idx'
endif

if !exists('ctk_temp_output')
    let ctk_temp_output = './tmp'
endif

" }}}2
" ctk_filetype_ext_var{{{2

if !exists('ctk_filetype_ext_var')
    if exists('cca_filetype_ext_var')
        let ctk_filetype_ext_var = cca_filetype_ext_var
    else
        let ctk_filetype_ext_var = 'ft_ext'
    endif
endif

" }}}2
" compiler info folder {{{2

if !exists('ctk_compiler_info_folder')
    if exists('cca_snippets_folder')
        let ctk_compiler_info_folder = cca_snippets_folder
    else
        let ctk_compiler_info_folder = 'snippets'
    endif
endif

" }}}2

" }}}1
" Commands, autocmds and meuus {{{1

command! -bar -bang RegisterCompiler call s:register_compiler('<bang>')
command! -bar UnRegisterCompiler call s:unregister_compiler()

command! -nargs=* -complete=customlist,s:info_name_complete -bar -count=0 
            \ ListCompiler call s:list_compiler(<q-args>, <count>)
command! -nargs=+ -complete=custom,s:info_item_complete -bang
            \ SetCompilerInfo call s:set_compiler_info(<q-args>, '<bang>')
command! -nargs=+ -complete=custom,s:info_item_complete -count=0
            \ AddFlags call s:add_flags(<q-args>, <count>)

command! -bar -count=1 Compile call s:compile(<count>)
command! -bar -count=1 Run call s:run(<count>)

augroup ctk_autocmd
    au!
    au VimEnter * RegisterCompiler | CTKtrace 'VimEnter:'.expand('<amatch>')
    au FileType * RegisterCompiler | CTKtrace 'FileType:'.expand('<amatch>')
augroup END

if exists('s:debug') && s:debug
    command! -nargs=+ CTKtrace echohl Search|echomsg 'ctk: '.<args>|echohl NONE
else
    command! -nargs=+ CTKtrace
endif

" }}}1
" ==========================================================
" main {{{1

" s:register_compiler {{{2

function! s:register_compiler(bang)
    if s:file_autoname() == 0
        if !exists('b:ctk') || a:bang == '!'
            call s:refresh_info(a:bang)
        endif
        if exists('b:ctk') && exists('b:ctk_generated_name')
            let b:ctk.generated_name = b:ctk_generated_name
            unlet b:ctk_generated_name
        endif
    endif
endfunction

" }}}2
" s:unregister_compiler {{{2

function! s:unregister_compiler()
    for map in b:ctk.unmap
        exec map
    endfor
    for info in b:ctk.info
        exec info.unmap
    endfor
    unlet b:ctk
endfunction

" }}}2
" s:compile {{{2

function! s:compile(count)
    " CTKtrace 'compile() called, a:000 = '.string(a:000)
    if s:find_source() || s:save_source()
                \ || a:count <= 0 || a:count > len(b:ctk.info)
        return 1
    endif

    if !has_key(b:ctk, 'cur_idx')
        let b:ctk.cur_idx = 0
    endif
    if !has_key(b:ctk, 'changedtick')
        let b:ctk.changedtick = b:changedtick
    endif
    if b:ctk.cur_idx != a:count - 1
                \ || b:ctk.changedtick != b:changedtick
        silent! unlet b:ctk.cur_info
        let b:ctk.cur_idx = a:count - 1
        let b:ctk.changedtick = b:changedtick
    endif

    if !has_key(b:ctk, 'cur_info')
        call s:prepare_info(b:ctk.cur_idx)
    endif
    let info = b:ctk.cur_info

    redraw
    echo 'Compiling ...'

    let cmd = s:prepare_compile_cmd(info.cc_cmd)
    let msg = 'Compiling... using '.get(info, 'title', info.name)
    let cfile = [msg, cmd, ''] + split(s:run_cmd(cmd), "\<NL>")
    let cfile += [info.name.' returned '.v:shell_error]
    call writefile(cfile, &errorfile)
    cgetfile

    redraw
    if v:shell_error != 0
        echo 'Compile Fail'
        copen
        return 1
    else
        echo 'Compile Successd!'
        cwindow
        return 0
    endif
endfunction

" }}}2
" s:run {{{2

function! s:run(count)
    if s:find_source() != 0
                \ || (!has_key(b:ctk, 'changedtick')
                \ || b:ctk.changedtick < b:changedtick
                \ || a:count - 1 != b:ctk.cur_idx)
                \ && s:compile(a:count) != 0
        return 1
    endif

    call s:find_source()
    let info = b:ctk.cur_info
    
    if has_key(info, 'debug')
                \ && has_key(info, 'debug_cmd')
                \ && info.debug_cmd != ''
        let cmd = info.debug_cmd
    elseif has_key(info, 'run_cmd')
                \ && info.run_cmd != ''
        let cmd = info.run_cmd
    else
        call s:echoerr("No run_cmd or debug_cmd in info")
        return
    endif

    if cmd !~ '^[:*]'
        if cmd[0] == '!'
            let cmd = cmd[1:]
        endif
        if has('win32') && executable('vimrun')
            let cmd = 'start vimrun '.cmd
            let cmd = ':!'.cmd
        elseif has('unix') && cmd =~ '$output'
                    \ && !executable(info.output)
            for output in ['"./".info.output',
                        \ 'fnamemodify(info.output, ":p")']
                if executable(output)
                    let info.output = output
                endif
            endfor
        endif
        let cmd = s:prepare_compile_cmd(cmd)
    endif

    if has('win32') && cmd =~ '^:!'
        call feedkeys("\<NL>", 't')
    endif
endfunction

" }}}2

" }}}1
" utility {{{1

" ctk:process_info {{{2

function! ctk:process_info(info)
    " CTKtrace 'process_flags: '.submatch(1).' = '.submatch(3)
    let a:info[submatch(1)] = s:strtrim(submatch(3))
    return ''
endfunction

" }}}2
" ctk:process_modeline {{{2

function! ctk:process_modeline(info)
    " CTKtrace 'process_flags: '.submatch(1).' = '.submatch(4)
    let val = s:strtrim(submatch(4))
    if !has_key(a:info, submatch(1))
        call s:echoerr("modeline: can't find '".submatch(1)."' in current info")
        return ''
    endif
    if submatch(2) != ''
        let a:info[submatch(1)] .= ' '.val
    else
        let a:info[submatch(1)] = val
    endif
    return ''
endfunction

" }}}2
" s:info_item_complete {{{2

function! s:info_item_complete(A,L,P)
    return "cc_cmd\ndebug_cmd\ndebug_flags\nflags\n".
                \ "hotkey\ninput\noutput\nrun_cmd\ntitle\n"
endfunction

" }}}2
" s:info_name_complete {{{2

function! s:info_name_complete(A,L,P)
    return sort(filter(map(copy(b:ctk.info), 'v:val.name'),
                \ "v:val =~ '^\\v".escape(a:A, '\')))
endfunction

" }}}2
" s:echoerr {{{2

function! s:echoerr(msg)
    echohl ErrorMsg
    echomsg 'ctk: '.a:msg
    echohl NONE
endfunction

" }}}2
" s:strtrim {{{2

function! s:strtrim(str)
    return matchstr(a:str, '^\s*\zs.\{-}\ze\s*$')
endfunction

" }}}2
" s:add_flags {{{2

function! s:add_flags(flags, count)
    if s:find_source()
        return
    endif

    if a:count > 0 && a:count <= len(b:ctk.info)
        let compiler = '-'.b:ctk.info[a:count - 1].name
    else
        let compiler = ''
    endif

    let com_begin = matchstr(&com, 's.\=:\zs[^,]\+\ze')
    if com_begin != ''
        let com_begin .= ' '
        let com_end = ' '.matchstr(&com, 'e.\=:\zs[^,]\+\ze')
    else
        let com_begin = matchstr(&com, ':\zs[^,]\+').' '
        let com_end = ''
    endif
    
    call append(line('$'), com_begin.'cc'.compiler.': '.a:flags.com_end)
endfunction

" }}}2
" s:show_list {{{2

function! s:show_list(info)
    echohl Title
    if has_key(a:info, 'title')
        echo a:info.title."\n\tname         = ".a:info.name."\n"
    else
        echo a:info.name."\n"
    endif
    echohl NONE

    for key in sort(filter(keys(a:info),
                \ "v:val !~ '".'title\|name\|unmap'."'"))
        echo printf("\t%-12s = %s", key, a:info[key])
    endfor
endfunction

" }}}2
" s:find_source{{{2
 
function! s:find_source()

    let cur_winnr = winnr()

    while 1
        if exists('b:ctk')
            return 0
        endif

        wincmd w

        if winnr() == cur_winnr
            call s:echoerr("Can't Find Source Window!")
            return 1
        endif
    endwhile
    
endfunction

" }}}2
" s:save_source {{{2

function! s:save_source()

    try
        silent write
    catch /E13/ " File exists
        redraw
        echohl Question
        echo "File Exists, Overwrite?(y/n)"
        echohl NONE

        if nr2char(getchar()) ==? 'y'
            silent write!
            return 0
        endif

        redraw
        echo "Nothing Done"
        return 1
    catch /E45/ " read only
    endtry

endfunction

" }}}2
" s:add_info {{{2

function! s:add_info(idx, name, info_text)
    let idx = a:idx
    if idx == -1
        " can't find name, add a new item
        let idx = len(b:ctk.info)
        call add(b:ctk.info, {'name': a:name})
        call add(b:ctk.unmap, s:mapping_keys(get(b:, 'ctk_compile_hotkey',
                    \ g:ctk_compile_hotkey), idx, 1, 0).
                    \ s:mapping_keys(get(b:, 'ctk_run_hotkey',
                    \ g:ctk_run_hotkey), idx, 0, 0))
    else
        exec b:ctk.info[idx].unmap
        let b:ctk.info[idx] = {'name': a:name}
    endif

    let info = b:ctk.info[idx]
    call substitute(a:info_text, '\v(<\w+)\s*\=\s*(\S)(.{-})\2',
                \ '\=ctk:process_info(info)', 'g')

    let info.unmap = ''
    if has_key(info, 'hotkey')
        let hotkey = ''
        for m in split(info.hotkey, '\\\@<!,')
            let m = substitute(m, '\\,', ',', 'g')
            let mlist = matchlist(m, '^\v(.):(.*)')
            if !empty(mlist) && mlist[1] =~ '^[cr]$'
                let info.unmap .= s:mapping_keys(mlist[2], idx,
                            \ mlist[1] == 'c', 1)
                let hotkey = mlist[1].':'.mlist[2].','
            endif
        endfor
        let info.hotkey = (hotkey == '' ? '<empty>' : hotkey[:-2])
    endif

    return s:set_default_flags(info, idx)
endfunction

" }}}2
" s:delete_info {{{2

function! s:delete_info(idx)
    if a:idx < 0 || a:dix >= len(b:ctk.info)
        return
    endif

    exec b:ctk.info.unmap
    unlet b:ctk.info[a:idx]
    unlet b:ctk.unmap[len(b:ctk.info)]
endfunction

" }}}2
" s:find_compilers {{{2

function! s:find_compilers(cp)
    let idx = 0

    for c in b:ctk.info
        if c.name == a:cp
            return idx
        endif
        let idx += 1
    endfor

    return -1
endfunction

" }}}2
" s:file_autoname {{{2

function! s:file_autoname()
    if exists('b:'.g:ctk_filetype_ext_var)
        let ext = b:{g:ctk_filetype_ext_var}
    elseif &ft != ''
        let ext = &ft
    else
        return 1
    endif

    if expand('%') != '' || &bt != ''
        return 0
    endif

    let temp_folder = get(b:, 'ctk_temp_folder', g:ctk_temp_folder)
    if !isdirectory(temp_folder)
        call mkdir(temp_folder, 'p')
    endif
    let temp_folder = fnamemodify(temp_folder, ':p')

    if exists('b:ctk_temp_folder')
        let b:ctk_temp_folder = temp_folder
    else
        let g:ctk_temp_folder = temp_folder
    endif

    if exists('b:ctk_auto_generated_fname')
        let fname = b:ctk_auto_generated_fname
    else
        let fname = g:ctk_auto_generated_fname
    endif

    if !exists('g:ctk_idx')
        let g:ctk_idx = 1
    endif
    let idx = g:ctk_idx
    while filereadable(temp_folder.'/'.eval(fname).'.'.ext)
        let idx += 1
    endwhile
    let g:ctk_idx = idx + 1

    if getcwd() == $VIMRUNTIME
        exec 'lcd '.temp_folder
    endif

    silent exec 'file '.simplify(fnamemodify(temp_folder.glob('/').
                \ eval(fname).'.'.ext, ':.'))

    let b:ctk_generated_name = expand('%:p')
endfunction

" }}}2
" s:refresh_info {{{2

function! s:refresh_info(bang)
    " CTKtrace 'refresh_info() called'
    if a:bang == '!'
        silent! call s:unregister_compiler()
    endif

    " use cca.vim 's command
    if exists(':RefreshSnippets') == 2
        RefreshSnippets
        return
    endif

    let sf = g:ctk_compiler_info_folder
    for name in split(&ft, '\.')
        exec 'run! '.sf.'/'.name.'.vim '.sf.'/'.name.'_*.vim '.
                    \ sf.'/'.name.'/*.vim'
    endfor
endfunction

" }}}2
" s:mapping_keys {{{2

function! s:mapping_keys(hotkey, idx, c, u)
    if a:hotkey =~ '$num'
        let lhs = join(map(split(a:idx+1, '\zs'),
                    \'substitute(a:hotkey, "$num", v:val, "g")'), '')
    else
        let lhs = substitute(a:hotkey, '$id', a:idx+1, 'g')
    endif
    let cmd = a:c ? 'Compile' : 'Run'
    let unq = a:u ? '<unique>' : ''
    let rhs = '<C-\><C-N>:'.(a:idx+1).cmd.'<CR><C-\><C-G>'
    let unmap = ''
    try
        exec 'noremap '.unq.' '.lhs.' '.rhs
        let unmap .= 'unmap '.lhs.'|'
    catch
    endtry

    if lhs =~ '^<\(lt\)\@!'
        try
            exec 'inoremap '.unq.' '.lhs.' '.rhs
            let unmap .= 'iunmap '.lhs.'|'
        catch
        endtry
    endif

    return ''
endfunction

" }}}2
" s:set_default_flags {{{2

function! s:set_default_flags(info, idx)
    for key in filter(keys(a:info), 'v:val =~ "cmd$"')
        if empty(a:info[key])
            let a:info[key] = '!$output'
        elseif  a:info[key] !~ '^[:!*]'
            let a:info[key] = '!'.a:info[key]
        endif
    endfor

    if !has_key(a:info, 'cc_cmd') || a:info.cc_cmd == ''
        let a:info.cc_cmd = ':ListCompiler cur'
    endif

    if !has_key(a:info, 'input') || a:info.input == ''
        let a:info.input = '%:.'
    endif

    if !has_key(a:info, 'output') || a:info.output == ''
        let a:info.output = '%:t:r'
    endif
endfunction

" }}}2
" s:set_compiler_info {{{2
" a:cmd - 'name': key=value...

function! s:set_compiler_info(cmd, bang)
    " build b:ctk, if need
    if !exists('b:ctk')
        let b:ctk = {}
        let b:ctk.info = []
        let b:ctk.unmap = []
        let b:ctk.cur_ft = &ft
    endif

    " find name and others
    let mlist = matchlist(a:cmd, '^\v\s*(.{-})%(\\@<!\s+(.*)\s*)=$')

    let name = s:strtrim(substitute(mlist[1], '\\\ze\s', '', 'g'))
    " is name appeared?
    let idx = s:find_compilers(name)
    if name != '' && mlist[2] != ''
        " CTKtrace 'set_compiler_info() name = '.name.', value = '.mlist[2]
        return s:add_info(idx, name, mlist[2])
    endif

    " no keys, means list or delete
    if a:bang != '!'
        call s:show_list(b:ctk.info[idx])
    elseif idx != -1
        call s:delete_info(idx)
        echo 'deleted item '.idx.' done'
    else
        call s:echoerr('no such compiler info: '.mlist[1])
    endif
endfunction

" }}}2
" s:list_compiler {{{2

function! s:list_compiler(name, count)
    if s:find_source()
        return
    endif

    if a:count > 0
        if a:count < len(b:ctk.info)
            call s:show_list(b:ctk.info[a:count - 1])
        else
            call s:echoerr("the counts of info is ".len(b:ctk.info)
        endif
    elseif (a:name ==? 'cur' || a:name == '') && has_key(b:ctk, 'cur_info')
        call s:show_list(b:ctk.cur_info)
    elseif a:name ==? 'all' || a:name == ''
        for info in b:ctk.info
            call s:show_list(info)
        endfor
    else
        let idx = s:find_compilers(a:name)
        if idx != -1
            call s:show_list(b:ctk.info[idx])
        else
            call s:echoerr("no such compiler info: ".a:name)
        endif
    endif
endfunction

" }}}2
" s:run_cmd {{{2

function! s:run_cmd(cmd)
    " CTKtrace 'run_cmd() called, cmd = '.a:cmd
    let mlist = matchlist(a:cmd, '\v^([!:*])=(.*)$')
    if mlist[1] == '!' || mlist[1] == ''
        return system(mlist[2])
    endif
    if mlist[1] == ':'
        redir => output
        silent! exec mlist[2]
        redir END
        return output
    endif
    if mlist[1] == '*'
        return eval(mlist[2])
    endif
    return ''
endfunction

" }}}2
" s:read_modeline {{{2

function! s:read_modeline(begin, end, info)
    " CTKtrace 'read_modeline() called, from '.a:begin.' to '.a:end
    let pat = '\v<cc%(-([^:]*))=:\s*(.*)'
    let pat2 = '\v(\w+)\s*(\+)=\=\s*(\S)(.{-})\3'
    let pos = winsaveview()

    call cursor(a:begin, 1)
    while search(pat, '', a:end) != 0
        let mlist = matchlist(getline('.'), pat)
        if mlist[1] == '' || a:info.name =~ '^\V'.escape(mlist[1], '\')
            call substitute(mlist[2], pat2,
                        \ '\=ctk:process_modeline(a:info)', 'g')
        endif
    endwhile

    call winrestview(pos)
endfunction

" }}}2
" s:prepare_info {{{2

function! s:prepare_info(idx)
    let b:ctk.cur_info = copy(b:ctk.info[a:idx])
    let info = b:ctk.cur_info
    let pat = '\v\\@<!%(\%|#\d*)(%(:[p8~.htre]|:g=s(.).{-}\2.{-}\2)*)'
    
    if has_key(b:ctk, 'generated_name')
                \ && b:ctk.generated_name == expand('%:p')
        let info.output = substitute(info.output, pat,
                    \ '\=fnamemodify("'.g:ctk_temp_output.'", submatch(1))', 'g')
        if info.output =~ '\s'
            let info.output = shellescape(info.output)
        endif
    endif

    if &modeline
        let end_line = line('$')
        if end_line <= &modelines * 2
            call s:read_modeline(1, end_line, info)
        else
            call s:read_modeline(1, &mls, info)
            call s:read_modeline(end_line-&mls+1, end_line, info)
        endif
    endif

    for key in ['input', 'output']
        let val = ''
        for file in split(info[key], '\\\@<!\s\+')
            let file = substitute(file, '\\\ze\s', '', 'g')
            if file !~ '\\\@<![#%]\%(:.\)*'
                let file = fnamemodify(file, ':.')
                if file =~ '\s'
                    let file = shellescape(file)
                endif
            endif
            let val .= file.' '
        endfor
        let info[key] = s:strtrim(val)
    endfor

    call map(info, "substitute(v:val, '".pat."', '".
                \ '\=expand(submatch(0))'."', 'g')")
    call map(info, "substitute(v:val, '".'\\\ze[#%]'."', '', 'g')")

    return info
endfunction

" }}}2
" s:prepare_compile_cmd {{{2

function! s:prepare_compile_cmd(cmd)
    if !has_key(b:ctk, 'cur_info')
        return
    endif

    let cmd = a:cmd
    let info = b:ctk.cur_info
    for key in filter(keys(info), 'v:val !~ "cmd$"')
        let cmd = substitute(cmd, '\c\\\@<!\$\V'.escape(key, '\'),
                    \ info[key], 'g')
    endfor

    " CTKtrace 'prepare_compile_cmd() cmd = '.cmd
    return substitute(cmd, '\$', '$', 'g')
endfunction

" }}}2

" }}}1
" ==========================================================
" restore cpo {{{1

let &cpo = old_cpo

" }}}1
" vim: ft=vim:ff=unix:fdm=marker:ts=4:sw=4:et:sta:nu
