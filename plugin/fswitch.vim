if exists("g:disable_fswitch")
    finish
endif

if v:version < 700
  echoerr "FSwitch requires Vim 7.0 or higher."
  finish
endif

let s:fswitch_version = '0.9.5'
let s:os_slash = &ssl == 0 && (has("win16") || has("win32") || has("win64")) ? '\' : '/'

" Default locations - appended to buffer locations unless otherwise specified
let s:fswitch_global_locs = '.' . s:os_slash

-G
function! s:SetVariables(dst, locs)
    if !exists("b:fswitchdst")
        let b:fswitchdst = a:dst
    endif
    if !exists("b:fswitchlocs")
        let b:fswitchlocs = a:locs
    endif
endfunction

function! s:FSGetLocations()
    let locations = []
    if exists("b:fswitchlocs")
        let locations = split(b:fswitchlocs, ',')
    endif
    if !exists("b:fsdisablegloc") || b:fsdisablegloc == 0
        let locations += split(s:fswitch_global_locs, ',')
    endif

    return locations
endfunction

function! s:FSGetFilenameMutations()
    if !exists("b:fswitchfnames")
        " For backward-compatibility out default mutation is an identity.
        return ['/^//']
    else
        return split(b:fswitchfnames, ',')
    endif
endfunction

function! s:FSGetMustMatch()
    let mustmatch = 1
    if exists("b:fsneednomatch") && b:fsneednomatch != 0
        let mustmatch = 0
    endif

    return mustmatch
endfunction

function! s:FSMutateFilename(filename, directive)
    let separator = strpart(a:directive, 0, 1)
    let dirparts = split(strpart(a:directive, 1), separator)
    if len(dirparts) < 2 || len(dirparts) > 3
        throw 'Bad mutation directive "' . a:directive . '".'
    else
        let flags = ''
        if len(dirparts) == 3
            let flags = dirparts[2]
        endif
        return substitute(a:filename, dirparts[0], dirparts[1], flags)
    endif
endfunction

function! s:FSGetAlternateFilename(filepath, filename, newextension, location, mustmatch)
    let parts = split(a:location, ':')
    let cmd = 'rel'
    let directive = parts[0]
    if len(parts) == 2
        let cmd = parts[0]
        let directive = parts[1]
    endif
    if cmd == 'reg' || cmd == 'ifrel' || cmd == 'ifabs'
        if strlen(directive) < 3
            throw 'Bad directive "' . a:location . '".'
        else
            let separator = strpart(directive, 0, 1)
            let dirparts = split(strpart(directive, 1), separator)
            if len(dirparts) < 2 || len(dirparts) > 3
                throw 'Bad directive "' . a:location . '".'
            else
                let part1 = dirparts[0]
                let part2 = dirparts[1]
                let flags = ''
                if len(dirparts) == 3
                    let flags = dirparts[2]
                endif
                if cmd == 'reg'
                    if a:mustmatch == 1 && match(a:filepath, part1) == -1
                        let path = ""
                    else
                        let path = substitute(a:filepath, part1, part2, flags) . s:os_slash .
                                    \ a:filename . '.' . a:newextension
                    endif
                elseif cmd == 'ifrel'
                    if match(a:filepath, part1) == -1
                        let path = ""
                    else
                        let path = a:filepath . s:os_slash . part2 .
                                     \ s:os_slash . a:filename . '.' . a:newextension
                    endif
                elseif cmd == 'ifabs'
                    if match(a:filepath, part1) == -1
                        let path = ""
                    else
                        let path = part2 . s:os_slash . a:filename . '.' . a:newextension
                    endif
                endif
            endif
        endif
    elseif cmd == 'rel'
        let path = a:filepath . s:os_slash . directive . s:os_slash . a:filename . '.' . a:newextension
    elseif cmd == 'abs'
        let path = directive . s:os_slash . a:filename . '.' . a:newextension
    endif

    return simplify(path)
endfunction

function! s:FSReturnCompanionFilename(filename, mustBeReadable)
    let fullpath = expand(a:filename . ':p:h')
	let ext = expand(a:filename . ':e')
	let justfile = expand(a:filename . ':t:r')
	let extensions = split(b:fswitchdst, ',')
	let filenameMutations = s:FSGetFilenameMutations()
    let locations = s:FSGetLocations()
    let mustmatch = s:FSGetMustMatch()
    let newpath = ''
    for currentExt in extensions
        for loc in locations
            for filenameMutation in filenameMutations
                let mutatedFilename = s:FSMutateFilename(justfile, filenameMutation)
                let newpath = s:FSGetAlternateFilename(fullpath, mutatedFilename, currentExt, loc, mustmatch)
                if a:mustBeReadable == 0 && newpath != ''
                    return newpath
                elseif a:mustBeReadable == 1
                    let newpath = glob(newpath)
                    if filereadable(newpath)
                        return newpath
                    endif
                endif
            endfor
        endfor
    endfor

    return newpath
endfunction


"
" FSwitch
"
" This is the only externally accessible function and is what we use to switch
" to the alternate file.
"
function! FSwitch(filename, precmd)
    if !exists("b:fswitchdst") || strlen(b:fswitchdst) == 0
        throw 'b:fswitchdst not set - read :help fswitch'
    endif
    if (!exists("b:fswitchlocs")   || strlen(b:fswitchlocs) == 0) &&
     \ (!exists("b:fsdisablegloc") || b:fsdisablegloc == 0)
        throw "There are no locations defined (see :h fswitchlocs and :h fsdisablegloc)"
    endif
    let newpath = s:FSReturnCompanionFilename(a:filename, 1)
	let openfile = 1
    if !filereadable(newpath)
        if exists("b:fsnonewfiles") || exists("g:fsnonewfiles")
            let openfile = 0
        else
            let newpath = s:FSReturnCompanionFilename(a:filename, 0)
		endif
    endif
    if &switchbuf =~ "^use"
        let i = 1
        let bufnum = winbufnr(i)
        while bufnum != -1
            let filename = fnamemodify(bufname(bufnum), ':p')
            if filename == newpath
                execute ":sbuffer " .  filename
                return
            endif
            let i += 1
            let bufnum = winbufnr(i)
        endwhile
    endif
    if openfile == 1
        if newpath != ''
            if strlen(a:precmd) != 0
                execute a:precmd
            endif
            let s:fname = fnameescape(newpath)

            if (strlen(bufname(s:fname))) > 0
                execute 'buffer ' . s:fname
            else
                execute 'edit ' . s:fname
            endif
        else
            echoerr "Alternate has evaluated to nothing.  See :h fswitch-empty for more info."
        endif
    else
        echoerr "No alternate file found.  'fsnonewfiles' is set which denies creation."
    endif
endfunction

augroup fswitch_au_group
    au!
    au BufEnter *.c    call s:SetVariables('h',       'reg:/src/include/,reg:|src|include/**|,ifrel:|/src/|../include|')
    au BufEnter *.cc   call s:SetVariables('hh',      'reg:/src/include/,reg:|src|include/**|,ifrel:|/src/|../include|')
    au BufEnter *.cpp  call s:SetVariables('hpp,h',   'reg:/src/include/,reg:|src|include/**|,ifrel:|/src/|../include|')
    au BufEnter *.cxx  call s:SetVariables('hxx',     'reg:/src/include/,reg:|src|include/**|,ifrel:|/src/|../include|')
    au BufEnter *.C    call s:SetVariables('H',       'reg:/src/include/,reg:|src|include/**|,ifrel:|/src/|../include|')
    au BufEnter *.m    call s:SetVariables('h',       'reg:/src/include/,reg:|src|include/**|,ifrel:|/src/|../include|')
    au BufEnter *.h    call s:SetVariables('c,cpp,m', 'reg:/include/src/,reg:/include.*/src/,ifrel:|/include/|../src|')
    au BufEnter *.hh   call s:SetVariables('cc',      'reg:/include/src/,reg:/include.*/src/,ifrel:|/include/|../src|')
    au BufEnter *.hpp  call s:SetVariables('cpp',     'reg:/include/src/,reg:/include.*/src/,ifrel:|/include/|../src|')
    au BufEnter *.hxx  call s:SetVariables('cxx',     'reg:/include/src/,reg:/include.*/src/,ifrel:|/include/|../src|')
    au BufEnter *.H    call s:SetVariables('C',       'reg:/include/src/,reg:/include.*/src/,ifrel:|/include/|../src|')
augroup END

com! FS      call FSwitch('%', '')
com! FSRight call FSwitch('%', 'WinMoveCommand "l"')
com! FSLeft  call FSwitch('%', 'WinMoveCommand "h"')
com! FSAbove call FSwitch('%', 'WinMoveCommand "k"')
com! FSBelow call FSwitch('%', 'WinMoveCommand "j"')
com! FSTab   call FSwitch('%', 'tabedit')

