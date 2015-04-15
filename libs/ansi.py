#!/usr/bin/python2 -O
# -*- coding: utf-8 -*-


import curses


class ANSIColor(dict):
    def __init__(self):
        if not self._instance:
            super(ANSIColor, self).__init__()
            try:
                curses.setupterm()
            except curses.error:
                return

            self['black']     = curses.tparm(curses.tigetstr('setaf'), 0)
            self['red']       = curses.tparm(curses.tigetstr('setaf'), 1)
            self['green']     = curses.tparm(curses.tigetstr('setaf'), 2)
            self['yellow']    = curses.tparm(curses.tigetstr('setaf'), 3)
            self['blue']      = curses.tparm(curses.tigetstr('setaf'), 4)
            self['magenta']   = curses.tparm(curses.tigetstr('setaf'), 5)
            self['cyan']      = curses.tparm(curses.tigetstr('setaf'), 6)
            self['white']     = curses.tparm(curses.tigetstr('setaf'), 7)

            self['bold']      = curses.tigetstr('bold')
            self['underline'] = curses.tigetstr('smul')
            self['inverse']   = curses.tigetstr('smso')
            self['normal']    = curses.tigetstr('sgr0')

    def __new__(cls, *p, **k):
        if not '_instance' in cls.__dict__:
            cls._instance = dict.__new__(cls, *p, **k)
        return cls._instance

    def __missing__(self, key):  # pylint: disable=W0613
        return ''
