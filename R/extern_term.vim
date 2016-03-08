
function StartR_ExternalTerm(rcmd)
    if g:R_notmuxconf
        let tmuxcnf = ' '
    else
        " Create a custom tmux.conf
        let cnflines = ['set-option -g prefix C-a',
                    \ 'unbind-key C-b',
                    \ 'bind-key C-a send-prefix',
                    \ 'set-window-option -g mode-keys vi',
                    \ 'set -g status off',
                    \ 'set -g default-terminal "screen-256color"',
                    \ "set -g terminal-overrides 'xterm*:smcup@:rmcup@'" ]

        if g:R_term == "rxvt" || g:R_term == "urxvt"
            let cnflines = cnflines + [
                        \ "set terminal-overrides 'rxvt*:smcup@:rmcup@'" ]
        endif

        call writefile(cnflines, g:rplugin_tmpdir . "/tmux.conf")
        let tmuxcnf = '-f "' . g:rplugin_tmpdir . "/tmux.conf" . '"'
    endif

    let rcmd = 'NVIMR_TMPDIR=' . substitute(g:rplugin_tmpdir, ' ', '\\ ', 'g') . ' NVIMR_COMPLDIR=' . substitute(g:rplugin_compldir, ' ', '\\ ', 'g') . ' NVIMR_ID=' . $NVIMR_ID . ' NVIMR_SECRET=' . $NVIMR_SECRET . ' R_DEFAULT_PACKAGES=' . $R_DEFAULT_PACKAGES . ' ' . a:rcmd

    call system("tmux -L NvimR has-session -t " . g:rplugin_tmuxsname)
    if v:shell_error
        if g:rplugin_is_darwin
            let rcmd = 'TERM=screen-256color ' . rcmd
            let opencmd = printf("tmux -L NvimR -2 %s new-session -s %s '%s'", tmuxcnf, g:rplugin_tmuxsname, rcmd)
            call writefile(["#!/bin/sh", opencmd], $NVIMR_TMPDIR . "/openR")
            call system("chmod +x '" . $NVIMR_TMPDIR . "/openR'")
            let opencmd = "open '" . $NVIMR_TMPDIR . "/openR'"
        else
            let opencmd = printf("%s tmux -L NvimR -2 %s new-session -s %s \"%s\" &", g:rplugin_termcmd, tmuxcnf, g:rplugin_tmuxsname, rcmd)
        endif
    else
        if g:rplugin_is_darwin
            call RWarningMsg("Tmux session with R is already running")
            return
        endif
        let opencmd = printf("%s tmux -L NvimR -2 %s attach-session -d -t %s &", g:rplugin_termcmd, tmuxcnf, g:rplugin_tmuxsname)
    endif

    if g:R_silent_term
        let rlog = system(opencmd)
        if v:shell_error
            call RWarningMsg(rlog)
            return
        endif
    else
        let initterm = ['cd "' . getcwd() . '"',
                    \ opencmd ]
        call writefile(initterm, g:rplugin_tmpdir . "/initterm_" . $NVIMR_ID . ".sh")
        let g:rplugin_jobs["Terminal emulator"] = jobstart("sh '" . g:rplugin_tmpdir . "/initterm_" . $NVIMR_ID . ".sh'", {'on_stderr': function('ROnJobStderr'), 'on_exit': function('ROnJobExit'), 'detach': 1})
    endif

    let g:SendCmdToR = function('SendCmdToR_Term')
    if WaitNvimcomStart()
        if g:R_after_start != ''
            call system(g:R_after_start)
        endif
    endif
    call delete(g:rplugin_tmpdir . "/initterm_" . $NVIMR_ID . ".sh")
    call delete(g:rplugin_tmpdir . "/openR")
endfunction

function SendCmdToR_Term(...)
    if g:R_ca_ck
        let cmd = "\001" . "\013" . a:1
    else
        let cmd = a:1
    endif

    " Send the command to R running in an external terminal emulator
    let str = substitute(cmd, "'", "'\\\\''", "g")
    if str =~ '^-'
        let str = ' ' . str
    endif
    if a:0 == 2 && a:2 == 0
        let scmd = "tmux -L NvimR set-buffer '" . str . "' && tmux -L NvimR paste-buffer -t " . g:rplugin_tmuxsname . '.0'
    else
        let scmd = "tmux -L NvimR set-buffer '" . str . "\<C-M>' && tmux -L NvimR paste-buffer -t " . g:rplugin_tmuxsname . '.0'
    endif
    let rlog = system(scmd)
    if v:shell_error
        let rlog = substitute(rlog, '\n', ' ', 'g')
        let rlog = substitute(rlog, '\r', ' ', 'g')
        call RWarningMsg(rlog)
        call ClearRInfo()
        return 0
    endif
    return 1
endfunction

" The Object Browser can run in a Tmux pane only if Neovim is inside a Tmux session
let g:R_objbr_place = substitute(g:R_objbr_place, "console", "script", "")

if g:rplugin_is_darwin
    finish
endif

call RSetDefaultValue("g:R_silent_term", 0)

" Choose a terminal (code adapted from screen.vim)
if exists("g:R_term")
    if !executable(g:R_term)
        call RWarningMsgInp("'" . g:R_term . "' not found. Please change the value of 'R_term' in your vimrc.")
        let g:R_term = "xterm"
    endif
endif

if !exists("g:R_term")
    let s:terminals = ['gnome-terminal', 'konsole', 'xfce4-terminal', 'Eterm',
                \ 'rxvt', 'urxvt', 'aterm', 'roxterm', 'terminator', 'lxterminal', 'xterm']
    for s:term in s:terminals
        if executable(s:term)
            let g:R_term = s:term
            break
        endif
    endfor
    unlet s:term
    unlet s:terminals
endif

if !exists("g:R_term") && !exists("g:R_term_cmd")
    call RWarningMsgInp("Please, set the variable 'g:R_term_cmd' in your vimrc. Read the plugin documentation for details.")
    let g:rplugin_failed = 1
    finish
endif

let g:rplugin_termcmd = g:R_term

if g:R_term =~ '^\(gnome-terminal\|xfce4-terminal\|roxterm\|terminator\|Eterm\|aterm\|lxterminal\|rxvt\|urxvt\)$'
    let g:rplugin_termcmd = g:rplugin_termcmd . " --title R"
elseif g:R_term == '^\(xterm\|uxterm\|lxterm\)$'
    let g:rplugin_termcmd = g:rplugin_termcmd . " -title R"
endif

if !g:R_nvim_wd
    if g:R_term =~ '^\(gnome-terminal\|xfce4-terminal\|terminator\|lxterminal\)$'
        let g:rplugin_termcmd = g:R_term . " --working-directory='" . expand("%:p:h") . "'"
    elseif g:R_term == "konsole"
        let g:rplugin_termcmd = "konsole --workdir '" . expand("%:p:h") . "'"
    elseif g:R_term == "roxterm"
        let g:rplugin_termcmd = "roxterm --directory='" . expand("%:p:h") . "'"
    endif
endif

if g:R_term == "gnome-terminal" || g:R_term == "xfce4-terminal"
    let g:rplugin_termcmd = g:rplugin_termcmd . " -x"
else
    let g:rplugin_termcmd = g:rplugin_termcmd . " -e"
endif

" Override default settings:
if exists("g:R_term_cmd")
    let g:rplugin_termcmd = g:R_term_cmd
endif
