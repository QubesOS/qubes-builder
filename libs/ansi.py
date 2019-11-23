#!/usr/bin/python3 -O
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

            self['black'] = curses.tparm(curses.tigetstr('setaf'), 0).decode(
                'utf-8')
            self['red'] = curses.tparm(curses.tigetstr('setaf'), 1).decode(
                'utf-8')
            self['green'] = curses.tparm(curses.tigetstr('setaf'), 2).decode(
                'utf-8')
            self['yellow'] = curses.tparm(curses.tigetstr('setaf'), 3).decode(
                'utf-8')
            self['blue'] = curses.tparm(curses.tigetstr('setaf'), 4).decode(
                'utf-8')
            self['magenta'] = curses.tparm(curses.tigetstr('setaf'), 5).decode(
                'utf-8')
            self['cyan'] = curses.tparm(curses.tigetstr('setaf'), 6).decode(
                'utf-8')
            self['white'] = curses.tparm(curses.tigetstr('setaf'), 7).decode(
                'utf-8')

            self['bold'] = curses.tigetstr('bold').decode('utf-8')
            self['underline'] = curses.tigetstr('smul').decode('utf-8')
            self['inverse'] = curses.tigetstr('smso').decode('utf-8')
            self['normal'] = curses.tigetstr('sgr0').decode('utf-8')

    def __new__(cls, *p, **k):
        if '_instance' not in cls.__dict__:
            cls._instance = dict.__new__(cls, *p, **k)
        return cls._instance

    def __missing__(self, key):  # pylint: disable=W0613
        return ''
