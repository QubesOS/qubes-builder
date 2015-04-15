# dialog.py --- A Python interface to the ncurses-based "dialog" utility
# -*- coding: utf-8 -*-
#
# Copyright (C) 2002, 2003, 2004, 2009, 2010, 2013  Florent Rougon
# Copyright (C) 2004  Peter Åstrand
# Copyright (C) 2000  Robb Shecter, Sultanbek Tezadov
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA  02110-1301 USA.

"""Python interface to dialog-like programs.

This module provides a Python interface to dialog-like programs such
as 'dialog' and 'Xdialog'.

It provides a Dialog class that retains some parameters such as the
program name and path as well as the values to pass as DIALOG*
environment variables to the chosen program.

For a quick start, you should look at the simple_example.py file that
comes with pythondialog. It is a very simple and straightforward
example using a few basic widgets. Then, you could study the demo.py
file that illustrates most features of pythondialog, or more directly
dialog.py.

See the Dialog class documentation for general usage information,
list of available widgets and ways to pass options to dialog.


Notable exceptions
------------------

Here is the hierarchy of notable exceptions raised by this module:

  error
     ExecutableNotFound
     BadPythonDialogUsage
     PythonDialogSystemError
        PythonDialogOSError
           PythonDialogIOError  (should not be raised starting from
                                Python 3.3, as IOError becomes an
                                alias of OSError)
        PythonDialogErrorBeforeExecInChildProcess
        PythonDialogReModuleError
     UnexpectedDialogOutput
     DialogTerminatedBySignal
     DialogError
     UnableToCreateTemporaryDirectory
     UnableToRetrieveBackendVersion
     UnableToParseBackendVersion
        UnableToParseDialogBackendVersion
     InadequateBackendVersion
     PythonDialogBug
     ProbablyPythonBug

As you can see, every exception 'exc' among them verifies:

  issubclass(exc, error)

so if you don't need fine-grained error handling, simply catch
'error' (which will probably be accessible as dialog.error from your
program) and you should be safe.

Changed in version 2.12: PythonDialogIOError is now a subclass of
PythonDialogOSError in order to help with the transition from IOError
to OSError in the Python language. With this change, you can safely
replace "except PythonDialogIOError" clauses with
"except PythonDialogOSError" even if running under Python < 3.3.

"""

from __future__ import with_statement, unicode_literals, print_function
import collections
from itertools import imap
from itertools import izip
from io import open
import locale

_VersionInfo = collections.namedtuple(
    "VersionInfo", ("major", "minor", "micro", "releasesuffix"))

class VersionInfo(_VersionInfo):
    def __unicode__(self):
        res = ".".join( ( unicode(elt) for elt in self[:3] ) )
        if self.releasesuffix:
            res += self.releasesuffix
        return res

    def __repr__(self):
        # Unicode strings are not supported as the result of __repr__()
        # in Python 2.x (cf. <http://bugs.python.org/issue5876>).
        return b"{0}.{1}".format(__name__, _VersionInfo.__repr__(self))

version_info = VersionInfo(3, 0, 1, None)
__version__ = unicode(version_info)


import sys, os, tempfile, random, re, warnings, traceback
from contextlib import contextmanager
from textwrap import dedent

# This is not for calling programs, only to prepare the shell commands that are
# written to the debug log when debugging is enabled.
try:
    from shlex import quote as _shell_quote
except ImportError:
    def _shell_quote(s):
        return "'%s'" % s.replace("'", "'\"'\"'")

# Exceptions raised by this module
#
# When adding, suppressing, renaming exceptions or changing their
# hierarchy, don't forget to update the module's docstring.
class error(Exception):
    """Base class for exceptions in pythondialog."""
    def __init__(self, message=None):
        self.message = message

    def __unicode__(self):
        return self.complete_message()

    def __repr__(self):
        # Unicode strings are not supported as the result of __repr__()
        # in Python 2.x (cf. <http://bugs.python.org/issue5876>).
        return b"{0}.{1}({2!r})".format(__name__, self.__class__.__name__,
                                        self.message)

    def complete_message(self):
        if self.message:
            return "{0}: {1}".format(self.ExceptionShortDescription,
                                     self.message)
        else:
            return self.ExceptionShortDescription

    ExceptionShortDescription = "{0} generic exception".format("pythondialog")

# For backward-compatibility
#
# Note: this exception was not documented (only the specific ones were), so
#       the backward-compatibility binding could be removed relatively easily.
PythonDialogException = error

class ExecutableNotFound(error):
    """Exception raised when the dialog executable can't be found."""
    ExceptionShortDescription = "Executable not found"

class PythonDialogBug(error):
    """Exception raised when pythondialog finds a bug in his own code."""
    ExceptionShortDescription = "Bug in pythondialog"

# Yeah, the "Probably" makes it look a bit ugly, but:
#   - this is more accurate
#   - this avoids a potential clash with an eventual PythonBug built-in
#     exception in the Python interpreter...
class ProbablyPythonBug(error):
    """Exception raised when pythondialog behaves in a way that seems to \
indicate a Python bug."""
    ExceptionShortDescription = "Bug in python, probably"

class BadPythonDialogUsage(error):
    """Exception raised when pythondialog is used in an incorrect way."""
    ExceptionShortDescription = "Invalid use of pythondialog"

class PythonDialogSystemError(error):
    """Exception raised when pythondialog cannot perform a "system \
operation" (e.g., a system call) that should work in "normal" situations.

    This is a convenience exception: PythonDialogIOError, PythonDialogOSError
    and PythonDialogErrorBeforeExecInChildProcess all derive from this
    exception. As a consequence, watching for PythonDialogSystemError instead
    of the aformentioned exceptions is enough if you don't need precise
    details about these kinds of errors.

    Don't confuse this exception with Python's builtin SystemError
    exception.

    """
    ExceptionShortDescription = "System error"

class PythonDialogOSError(PythonDialogSystemError):
    """Exception raised when pythondialog catches an OSError exception that \
should be passed to the calling program."""
    ExceptionShortDescription = "OS error"

class PythonDialogIOError(PythonDialogOSError):
    """Exception raised when pythondialog catches an IOError exception that \
should be passed to the calling program.

    This exception should not be raised starting from Python 3.3, as
    the built-in exception IOError becomes an alias of OSError.

    """
    ExceptionShortDescription = "IO error"

class PythonDialogErrorBeforeExecInChildProcess(PythonDialogSystemError):
    """Exception raised when an exception is caught in a child process \
before the exec sytem call (included).

    This can happen in uncomfortable situations such as:
      - the system being out of memory;
      - the maximum number of open file descriptors being reached;
      - the dialog-like program being removed (or made
        non-executable) between the time we found it with
        _find_in_path and the time the exec system call attempted to
        execute it;
      - the Python program trying to call the dialog-like program
        with arguments that cannot be represented in the user's
        locale (LC_CTYPE)."""
    ExceptionShortDescription = "Error in a child process before the exec " \
                                "system call"

class PythonDialogReModuleError(PythonDialogSystemError):
    """Exception raised when pythondialog catches a re.error exception."""
    ExceptionShortDescription = "'re' module error"

class UnexpectedDialogOutput(error):
    """Exception raised when the dialog-like program returns something not \
expected by pythondialog."""
    ExceptionShortDescription = "Unexpected dialog output"

class DialogTerminatedBySignal(error):
    """Exception raised when the dialog-like program is terminated by a \
signal."""
    ExceptionShortDescription = "dialog-like terminated by a signal"

class DialogError(error):
    """Exception raised when the dialog-like program exits with the \
code indicating an error."""
    ExceptionShortDescription = "dialog-like terminated due to an error"

class UnableToCreateTemporaryDirectory(error):
    """Exception raised when we cannot create a temporary directory."""
    ExceptionShortDescription = "Unable to create a temporary directory"

class UnableToRetrieveBackendVersion(error):
    """Exception raised when we cannot retrieve the version string of the \
dialog-like backend."""
    ExceptionShortDescription = "Unable to retrieve the version of the \
dialog-like backend"

class UnableToParseBackendVersion(error):
    """Exception raised when we cannot parse the version string of the \
dialog-like backend."""
    ExceptionShortDescription = "Unable to parse as a dialog-like backend \
version string"

class UnableToParseDialogBackendVersion(UnableToParseBackendVersion):
    """Exception raised when we cannot parse the version string of the dialog \
backend."""
    ExceptionShortDescription = "Unable to parse as a dialog version string"

class InadequateBackendVersion(error):
    """Exception raised when the backend version in use is inadequate \
in a given situation."""
    ExceptionShortDescription = "Inadequate backend version"


@contextmanager
def _OSErrorHandling():
    try:
        yield
    except OSError, e:
        raise PythonDialogOSError(unicode(e))
    except IOError, e:
        raise PythonDialogIOError(unicode(e))


try:
    # Values accepted for checklists
    _on_cre = re.compile(r"on$", re.IGNORECASE)
    _off_cre = re.compile(r"off$", re.IGNORECASE)

    _calendar_date_cre = re.compile(
        r"(?P<day>\d\d)/(?P<month>\d\d)/(?P<year>\d\d\d\d)$")
    _timebox_time_cre = re.compile(
        r"(?P<hour>\d\d):(?P<minute>\d\d):(?P<second>\d\d)$")
except re.error, e:
    raise PythonDialogReModuleError(unicode(e))


# From dialog(1):
#
#   All options begin with "--" (two ASCII hyphens, for the benefit of those
#   using systems with deranged locale support).
#
#   A "--" by itself is used as an escape, i.e., the next token on the
#   command-line is not treated as an option, as in:
#        dialog --title -- --Not an option
def _dash_escape(args):
    """Escape all elements of 'args' that need escaping.

    'args' may be any sequence and is not modified by this function.
    Return a new list where every element that needs escaping has
    been escaped.

    An element needs escaping when it starts with two ASCII hyphens
    ('--'). Escaping consists in prepending an element composed of
    two ASCII hyphens, i.e., the string '--'.

    """
    res = []

    for arg in args:
        if arg.startswith("--"):
            res.extend(("--", arg))
        else:
            res.append(arg)

    return res

# We need this function in the global namespace for the lambda
# expressions in _common_args_syntax to see it when they are called.
def _dash_escape_nf(args):      # nf: non-first
    """Escape all elements of 'args' that need escaping, except the first one.

    See _dash_escape() for details. Return a new list.

    """
    if not args:
        raise PythonDialogBug("not a non-empty sequence: {0!r}".format(args))
    l = _dash_escape(args[1:])
    l.insert(0, args[0])
    return l

def _simple_option(option, enable):
    """Turn on or off the simplest dialog Common Options."""
    if enable:
        return (option,)
    else:
        # This will not add any argument to the command line
        return ()


# This dictionary allows us to write the dialog common options in a Pythonic
# way (e.g. dialog_instance.checklist(args, ..., title="Foo", no_shadow=True)).
#
# Options such as --separate-output should obviously not be set by the user
# since they affect the parsing of dialog's output:
_common_args_syntax = {
    "ascii_lines": lambda enable: _simple_option("--ascii-lines", enable),
    "aspect": lambda ratio: _dash_escape_nf(("--aspect", unicode(ratio))),
    "backtitle": lambda backtitle: _dash_escape_nf(("--backtitle", backtitle)),
    # Obsolete according to dialog(1)
    "beep": lambda enable: _simple_option("--beep", enable),
    # Obsolete according to dialog(1)
    "beep_after": lambda enable: _simple_option("--beep-after", enable),
    # Warning: order = y, x!
    "begin": lambda coords: _dash_escape_nf(
        ("--begin", unicode(coords[0]), unicode(coords[1]))),
    "cancel_label": lambda s: _dash_escape_nf(("--cancel-label", s)),
    # Old, unfortunate choice of key, kept for backward compatibility
    "cancel": lambda s: _dash_escape_nf(("--cancel-label", s)),
    "clear": lambda enable: _simple_option("--clear", enable),
    "colors": lambda enable: _simple_option("--colors", enable),
    "column_separator": lambda s: _dash_escape_nf(("--column-separator", s)),
    "cr_wrap": lambda enable: _simple_option("--cr-wrap", enable),
    "create_rc": lambda filename: _dash_escape_nf(("--create-rc", filename)),
    "date_format": lambda s: _dash_escape_nf(("--date-format", s)),
    "defaultno": lambda enable: _simple_option("--defaultno", enable),
    "default_button": lambda s: _dash_escape_nf(("--default-button", s)),
    "default_item": lambda s: _dash_escape_nf(("--default-item", s)),
    "exit_label": lambda s: _dash_escape_nf(("--exit-label", s)),
    "extra_button": lambda enable: _simple_option("--extra-button", enable),
    "extra_label": lambda s: _dash_escape_nf(("--extra-label", s)),
    "help": lambda enable: _simple_option("--help", enable),
    "help_button": lambda enable: _simple_option("--help-button", enable),
    "help_label": lambda s: _dash_escape_nf(("--help-label", s)),
    "help_status": lambda enable: _simple_option("--help-status", enable),
    "help_tags": lambda enable: _simple_option("--help-tags", enable),
    "hfile": lambda filename: _dash_escape_nf(("--hfile", filename)),
    "hline": lambda s: _dash_escape_nf(("--hline", s)),
    "ignore": lambda enable: _simple_option("--ignore", enable),
    "insecure": lambda enable: _simple_option("--insecure", enable),
    "item_help": lambda enable: _simple_option("--item-help", enable),
    "keep_tite": lambda enable: _simple_option("--keep-tite", enable),
    "keep_window": lambda enable: _simple_option("--keep-window", enable),
    "max_input": lambda size: _dash_escape_nf(("--max-input", unicode(size))),
    "no_cancel": lambda enable: _simple_option("--no-cancel", enable),
    "nocancel": lambda enable: _simple_option("--nocancel", enable),
    "no_collapse": lambda enable: _simple_option("--no-collapse", enable),
    "no_kill": lambda enable: _simple_option("--no-kill", enable),
    "no_label": lambda s: _dash_escape_nf(("--no-label", s)),
    "no_lines": lambda enable: _simple_option("--no-lines", enable),
    "no_mouse": lambda enable: _simple_option("--no-mouse", enable),
    "no_nl_expand": lambda enable: _simple_option("--no-nl-expand", enable),
    "no_ok": lambda enable: _simple_option("--no-ok", enable),
    "no_shadow": lambda enable: _simple_option("--no-shadow", enable),
    "no_tags": lambda enable: _simple_option("--no-tags", enable),
    "ok_label": lambda s: _dash_escape_nf(("--ok-label", s)),
    # cf. Dialog.maxsize()
    "print_maxsize": lambda enable: _simple_option("--print-maxsize",
                                                   enable),
    "print_size": lambda enable: _simple_option("--print-size", enable),
    # cf. Dialog.backend_version()
    "print_version": lambda enable: _simple_option("--print-version",
                                                   enable),
    "scrollbar": lambda enable: _simple_option("--scrollbar", enable),
    "separate_output": lambda enable: _simple_option("--separate-output",
                                                     enable),
    "separate_widget": lambda s: _dash_escape_nf(("--separate-widget", s)),
    "shadow": lambda enable: _simple_option("--shadow", enable),
    # Obsolete according to dialog(1)
    "size_err": lambda enable: _simple_option("--size-err", enable),
    "sleep": lambda secs: _dash_escape_nf(("--sleep", unicode(secs))),
    "stderr": lambda enable: _simple_option("--stderr", enable),
    "stdout": lambda enable: _simple_option("--stdout", enable),
    "tab_correct": lambda enable: _simple_option("--tab-correct", enable),
    "tab_len": lambda n: _dash_escape_nf(("--tab-len", unicode(n))),
    "time_format": lambda s: _dash_escape_nf(("--time-format", s)),
    "timeout": lambda secs: _dash_escape_nf(("--timeout", unicode(secs))),
    "title": lambda title: _dash_escape_nf(("--title", title)),
    "trace": lambda filename: _dash_escape_nf(("--trace", filename)),
    "trim": lambda enable: _simple_option("--trim", enable),
    "version": lambda enable: _simple_option("--version", enable),
    "visit_items": lambda enable: _simple_option("--visit-items", enable),
    "yes_label": lambda s: _dash_escape_nf(("--yes-label", s)) }


def _find_in_path(prog_name):
    """Search an executable in the PATH.

    If PATH is not defined, the default path ":/bin:/usr/bin" is
    used.

    Return a path to the file or None if no readable and executable
    file is found.

    Notable exception: PythonDialogOSError

    """
    with _OSErrorHandling():
        # Note that the leading empty component in the default value for PATH
        # could lead to the returned path not being absolute.
        PATH = os.getenv("PATH", ":/bin:/usr/bin") # see the execvp(3) man page
        for d in PATH.split(":"):
            file_path = os.path.join(d, prog_name)
            if os.path.isfile(file_path) \
               and os.access(file_path, os.R_OK | os.X_OK):
                return file_path
        return None


def _path_to_executable(f):
    """Find a path to an executable.

    Find a path to an executable, using the same rules as the POSIX
    exec*p functions (see execvp(3) for instance).

    If 'f' contains a '/', it is assumed to be a path and is simply
    checked for read and write permissions; otherwise, it is looked
    for according to the contents of the PATH environment variable,
    which defaults to ":/bin:/usr/bin" if unset.

    The returned path is not necessarily absolute.

    Notable exceptions:

        ExecutableNotFound
        PythonDialogOSError

    """
    with _OSErrorHandling():
        if '/' in f:
            if os.path.isfile(f) and \
                   os.access(f, os.R_OK | os.X_OK):
                res = f
            else:
                raise ExecutableNotFound("%s cannot be read and executed" % f)
        else:
            res = _find_in_path(f)
            if res is None:
                raise ExecutableNotFound(
                    "can't find the executable for the dialog-like "
                    "program")

    return res


def _to_onoff(val):
    """Convert boolean expressions to "on" or "off".

    Return:
      - "on" if 'val' is True, a non-zero integer, "on" or any case
        variation thereof;
      - "off" if 'val' is False, 0, "off" or any case variation thereof.

    Notable exceptions:

        PythonDialogReModuleError
        BadPythonDialogUsage

    """
    if isinstance(val, (bool, int)):
        return "on" if val else "off"
    elif isinstance(val, basestring):
        try:
            if _on_cre.match(val):
                return "on"
            elif _off_cre.match(val):
                return "off"
        except re.error, e:
            raise PythonDialogReModuleError(unicode(e))

    raise BadPythonDialogUsage("invalid boolean value: {0!r}".format(val))


def _compute_common_args(mapping):
    """Compute the list of arguments for dialog common options.

    Compute a list of the command-line arguments to pass to dialog
    from a keyword arguments dictionary for options listed as "common
    options" in the manual page for dialog. These are the options
    that are not tied to a particular widget.

    This allows to specify these options in a pythonic way, such as:

       d.checklist(<usual arguments for a checklist>,
                   title="...",
                   backtitle="...")

    instead of having to pass them with strings like "--title foo" or
    "--backtitle bar".

    Notable exceptions: None

    """
    args = []
    for option, value in mapping.items():
        args.extend(_common_args_syntax[option](value))
    return args


def _create_temporary_directory():
    """Create a temporary directory (securely).

    Return the directory path.

    Notable exceptions:
        - UnableToCreateTemporaryDirectory
        - PythonDialogOSError
        - exceptions raised by the tempfile module

    """
    find_temporary_nb_attempts = 5
    for i in xrange(find_temporary_nb_attempts):
        with _OSErrorHandling():
            tmp_dir = os.path.join(tempfile.gettempdir(),
                                   "%s-%d" \
                                   % ("pythondialog",
                                      random.randint(0, sys.maxsize)))
        try:
            os.mkdir(tmp_dir, 0700)
        except os.error:
            continue
        else:
            break
    else:
        raise UnableToCreateTemporaryDirectory(
            "somebody may be trying to attack us")

    return tmp_dir


# Classes for dealing with the version of dialog-like backend programs
if sys.hexversion >= 0x030200F0:
    import abc
    # Abstract base class
    class BackendVersion():
        __metaclass__ = abc.ABCMeta
        @abc.abstractmethod
        def __unicode__(self):
            raise NotImplementedError()

        if sys.hexversion >= 0x030300F0:
            @classmethod
            @abc.abstractmethod
            def fromstring(cls, s):
                raise NotImplementedError()
        else:                   # for Python 3.2
            @abc.abstractclassmethod
            def fromstring(cls, s):
                raise NotImplementedError()

        @abc.abstractmethod
        def __lt__(self, other):
            raise NotImplementedError()

        @abc.abstractmethod
        def __le__(self, other):
            raise NotImplementedError()

        @abc.abstractmethod
        def __eq__(self, other):
            raise NotImplementedError()

        @abc.abstractmethod
        def __ne__(self, other):
            raise NotImplementedError()

        @abc.abstractmethod
        def __gt__(self, other):
            raise NotImplementedError()

        @abc.abstractmethod
        def __ge__(self, other):
            raise NotImplementedError()
else:
    class BackendVersion(object):
        pass


class DialogBackendVersion(BackendVersion):
    """Class representing possible versions of the dialog backend.

    The purpose of this class is to make it easy to reliably compare
    between versions of the dialog backend. It encapsulates the
    specific details of the backend versioning scheme to allow
    eventual adaptations to changes in this scheme without affecting
    external code.

    The version is represented by two components in this class: the
    "dotted part" and the "rest". For instance, in the '1.2' version
    string, the dotted part is [1, 2] and the rest is the empty
    string. However, in version '1.2-20130902', the dotted part is
    still [1, 2], but the rest is the string '-20130902'.

    Instances of this class can be created with the constructor by
    specifying the dotted part and the rest. Alternatively, an
    instance can be created from the corresponding version string
    (e.g., '1.2-20130902') using the fromstring() class method. This
    is particularly useful with the result of d.backend_version(),
    where 'd' is a Dialog instance. Actually, the main constructor
    detects if its first argument is a string and calls fromstring()
    in this case as a convenience. Therefore, all of the following
    expressions are valid to create a DialogBackendVersion instance:

      DialogBackendVersion([1, 2])
      DialogBackendVersion([1, 2], "-20130902")
      DialogBackendVersion("1.2-20130902")
      DialogBackendVersion.fromstring("1.2-20130902")

    If 'bv' is a DialogBackendVersion instance, unicode(bv) is a string
    representing the same version (for instance, "1.2-20130902").

    Two DialogBackendVersion instances can be compared with the usual
    comparison operators (<, <=, ==, !=, >=, >). The algorithm is
    designed so that the following order is respected (after
    instanciation with fromstring()):

      1.2 < 1.2-20130902 < 1.2-20130903 < 1.2.0 < 1.2.0-20130902

    among other cases. Actually, the "dotted parts" are the primary
    keys when comparing and "rest" strings act as secondary keys.
    Dotted parts are compared with the standard Python list
    comparison and "rest" strings using the standard Python string
    comparison.

    """
    try:
        _backend_version_cre = re.compile(r"""(?P<dotted> (\d+) (\.\d+)* )
                                              (?P<rest>.*)$""", re.VERBOSE)
    except re.error, e:
        raise PythonDialogReModuleError(unicode(e))

    def __init__(self, dotted_part_or_str, rest=""):
        """Create a DialogBackendVersion instance.

        Please see the class docstring for details.

        """
        if isinstance(dotted_part_or_str, basestring):
            if rest:
                raise BadPythonDialogUsage(
                    "non-empty 'rest' with 'dotted_part_or_str' as string: "
                    "{0!r}".format(rest))
            else:
                tmp = self.__class__.fromstring(dotted_part_or_str)
                dotted_part_or_str, rest = tmp.dotted_part, tmp.rest

        for elt in dotted_part_or_str:
            if not isinstance(elt, int):
                raise BadPythonDialogUsage(
                    "when 'dotted_part_or_str' is not a string, it must "
                    "be a sequence (or iterable) of integers; however, "
                    "{0!r} is not an integer.".format(elt))

        self.dotted_part = list(dotted_part_or_str)
        self.rest = rest

    def __repr__(self):
        # Unicode strings are not supported as the result of __repr__()
        # in Python 2.x (cf. <http://bugs.python.org/issue5876>).
        return b"{0}.{1}({2!r}, rest={3!r})".format(
            __name__, self.__class__.__name__, self.dotted_part, self.rest)

    def __unicode__(self):
        return '.'.join(imap(unicode, self.dotted_part)) + self.rest

    @classmethod
    def fromstring(cls, s):
        try:
            mo = cls._backend_version_cre.match(s)
            if not mo:
                raise UnableToParseDialogBackendVersion(s)
            dotted_part = [ int(x) for x in mo.group("dotted").split(".") ]
            rest = mo.group("rest")
        except re.error, e:
            raise PythonDialogReModuleError(unicode(e))

        return cls(dotted_part, rest)

    def __lt__(self, other):
        return (self.dotted_part, self.rest) < (other.dotted_part, other.rest)

    def __le__(self, other):
        return (self.dotted_part, self.rest) <= (other.dotted_part, other.rest)

    def __eq__(self, other):
        return (self.dotted_part, self.rest) == (other.dotted_part, other.rest)

    # Python 3.2 has a decorator (functools.total_ordering) to automate this.
    def __ne__(self, other):
        return not (self == other)

    def __gt__(self, other):
        return not (self <= other)

    def __ge__(self, other):
        return not (self < other)


def widget(func):
    """Decorator to mark Dialog methods that provide widgets.

    This allows code to perform automatic operations on these
    specific methods. For instance, one can define a class that
    behaves similarly to Dialog, except that after every
    widget-producing call, it spawns a "confirm quit" dialog if the
    widget returned Dialog.ESC, and loops in case the user doesn't
    actually want to quit.

    When it is unclear whether a method should have the decorator or
    not, the return value is used to draw the line. For instance,
    among 'gauge_start', 'gauge_update' and 'gauge_stop', only the
    last one has the decorator because it returns a Dialog exit code,
    whereas the first two don't return anything meaningful.

    Note:

      Some widget-producing methods return the Dialog exit code, but
      other methods return a *sequence*, the first element of which
      is the Dialog exit code; the 'retval_is_code' attribute, which
      is set by the decorator of the same name, allows to
      programmatically discover the interface a given method conforms
      to.

    """
    func.is_widget = True
    return func


def retval_is_code(func):
    """Decorator for Dialog widget-producing methods whose return value is \
the Dialog exit code.

    This decorator is intended for widget-producing methods whose
    return value consists solely of the Dialog exit code. When this
    decorator is *not* used on a widget-producing method, the Dialog
    exit code must be the first element of the return value.

    """
    func.retval_is_code = True
    return func


def _obsolete_property(name, replacement=None):
    if replacement is None:
        replacement = name

    def getter(self):
        warnings.warn("the DIALOG_{name} attribute of Dialog instances is "
                      "obsolete; use the Dialog.{repl} class attribute "
                      "instead.".format(name=name, repl=replacement),
                      DeprecationWarning)
        return getattr(self, replacement)

    return getter


# Main class of the module
class Dialog(object):
    """Class providing bindings for dialog-compatible programs.

    This class allows you to invoke dialog or a compatible program in
    a pythonic way to build quicky and easily simple but nice text
    interfaces.

    An application typically creates one instance of the Dialog class
    and uses it for all its widgets, but it is possible to
    concurrently use several instances of this class with different
    parameters (such as the background title) if you have a need
    for this.


    Public methods of the Dialog class (mainly widgets)
    ===================================================

    The Dialog class has the following methods that produce or update
    widgets:

      buildlist
      calendar
      checklist
      dselect
      editbox
      form
      fselect

      gauge_start
      gauge_update
      gauge_stop

      infobox
      inputbox
      inputmenu
      menu
      mixedform
      mixedgauge
      msgbox
      passwordbox
      passwordform
      pause
      programbox
      progressbox
      radiolist
      rangebox
      scrollbox
      tailbox
      textbox
      timebox
      treeview
      yesno

    All these widgets are described in the docstrings of the
    corresponding Dialog methods. Many of these descriptions are
    adapted from the dialog(1) manual page, with the kind permission
    of Thomas Dickey.

    The Dialog class also has a few other methods, that are not
    related to a particular widget:

      add_persistent_args
      backend_version       (see "Checking the backend version" below)
      maxsize
      set_background_title

      clear                 (has been OBSOLETE for many years!)
      setBackgroundTitle    (has been OBSOLETE for many years!)


    Passing dialog "Common Options"
    ===============================

    Every widget method has a **kwargs argument allowing you to pass
    dialog so-called Common Options (see the dialog(1) manual page)
    to dialog for this widget call. For instance, if 'd' is a Dialog
    instance, you can write:

      d.checklist(args, ..., title="A Great Title", no_shadow=True)

    The no_shadow option is worth looking at:

      1. It is an option that takes no argument as far as dialog is
         concerned (unlike the "--title" option, for instance). When
         you list it as a keyword argument, the option is really
         passed to dialog only if the value you gave it evaluates to
         True in a boolean context. For instance, "no_shadow=True"
         will cause "--no-shadow" to be passed to dialog whereas
         "no_shadow=False" will cause this option not to be passed to
         dialog at all.

      2. It is an option that has a hyphen (-) in its name, which you
         must change into an underscore (_) to pass it as a Python
         keyword argument. Therefore, "--no-shadow" is passed by
         giving a "no_shadow=True" keyword argument to a Dialog method
         (the leading two dashes are also consistently removed).


    Return value of widget-producing methods
    ========================================

    Most Dialog methods that create a widget (actually: all methods
    that supervise the exit of a widget) return a value which fits
    into one of these categories:

      1. The return value is a Dialog exit code (see below).

      2. The return value is a sequence whose first element is a
         Dialog exit code (the rest of the sequence being related to
         what the user entered in the widget).

    "Dialog exit code" (high-level)
    -------------------------------
    A Dialog exit code is a string such as "ok", "cancel", "esc",
    "help" and "extra", respectively available as Dialog.OK,
    Dialog.CANCEL, Dialog.ESC, Dialog.HELP and Dialog.EXTRA, i.e.
    attributes of the Dialog class. These are the standard Dialog
    exit codes, also known as "high-level exit codes", that user code
    should deal with. They indicate how/why the widget ended. Some
    widgets may return additional, non-standard exit codes; for
    instance, the inputmenu widget may return "accepted" or "renamed"
    in addition to the standard Dialog exit codes.

    When getting a Dialog exit code from a widget-producing method,
    user code should compare it with Dialog.OK and friends (or
    equivalently, with "ok" and friends) using the == operator. This
    allows to easily replace Dialog.OK and friends with objects that
    compare the same with "ok" and u"ok" in Python 2, for instance.

    "dialog exit status" (low-level)
    --------------------------------
    The standard Dialog exit codes are derived from the dialog exit
    status, also known as "low-level exit code". This low-level exit
    code is an integer returned by the dialog backend whose different
    possible values are referred to as DIALOG_OK, DIALOG_CANCEL,
    DIALOG_ESC, DIALOG_ERROR, DIALOG_EXTRA, DIALOG_HELP and
    DIALOG_ITEM_HELP in the dialog(1) manual page. Note that:
      - DIALOG_HELP and DIALOG_ITEM_HELP both map to Dialog.HELP in
        pythondialog, because they both correspond to the same user
        action and the difference brings no information that the
        caller does not already have;
      - DIALOG_ERROR has no counterpart as a Dialog attribute,
        because it is automatically translated into a DialogError
        exception when received.

    In pythondialog 2.x, the low-level exit codes were available
    as the DIALOG_OK, DIALOG_CANCEL, etc. attributes of Dialog
    instances. For compatibility, the Dialog class has attributes of
    the same names mapped to Dialog.OK, Dialog.CANCEL, etc., but
    their use is deprecated as of pythondialog 3.0.


    Adding a Extra button
    =====================

    With most widgets, it is possible to add a supplementary button
    called "Extra button". To do that, you simply have to use
    'extra_button=True' (keyword argument) in the widget call.
    By default, the button text is "Extra", but you can specify
    another string with the 'extra_label' keyword argument.

    When the widget exits, you know if the Extra button was pressed
    if the Dialog exit code is Dialog.EXTRA ("extra"). Normally, the
    rest of the return value is the same as if the widget had been
    closed with OK. Therefore, if the widget normally returns a list
    of three integers, for instance, you can expect to get the same
    information if Extra is pressed instead of OK.


    Providing on-line help facilities
    =================================

    With most dialog widgets, it is possible to provide online help
    to the final user. At the time of this writing (October 2013),
    there are three main options governing these help facilities in
    the dialog backend: --help-button, --item-help and --help-status.
    Since dialog 1.2-20130902, there is also --help-tags that
    modifies the way --item-help works. As explained previously, to
    use these options in pythondialog, you can pass the
    'help_button', 'item_help', 'help_status' and 'help_tags' keyword
    arguments to Dialog widget-producing methods.

    Adding a Help button
    --------------------
    In order to provide a Help button in addition to the normal
    buttons of a widget, you can pass help_button=True (keyword
    argument) to the corresponding Dialog method. For instance, if
    'd' is a Dialog instance, you can write:

      code = d.yesno("<text>", height=10, width=40, help_button=True)

    or

      code, answer = d.inputbox("<text>", init="<init>",
                                help_button=True)

    When the method returns, the exit code is Dialog.HELP (i.e., the
    string "help") if the user pressed the Help button. Apart from
    that, it works exactly as if 'help_button=True' had not been
    used. In the last example, if the user presses the Help button,
    'answer' will contain the user input, just as if OK had been
    pressed. Similarly, if you write:

      code, t = d.checklist(
                    "<text>", height=0, width=0, list_height=0,
                    choices=[ ("Tag 1", "Item 1", False),
                              ("Tag 2", "Item 2", True),
                              ("Tag 3", "Item 3", True) ],
                    help_button=True)

    and find that code == Dialog.HELP, then 't' contains the tag
    string for the highlighted item when the Help button was pressed.

    Finally, note that it is possible to choose the text written on
    the Help button by supplying a string as the 'help_label' keyword
    argument.

    Providing inline per-item help
    ------------------------------
    In addition to, or instead of the Help button, you can provide
    item-specific help that is normally displayed at the bottom of
    the widget. This can be done by passing the 'item_help=True'
    keyword argument to the widget-producing method and by including
    the item-specific help strings in the appropriate argument.

    For widgets where item-specific help makes sense (i.e., there are
    several elements that can be highlighted), there is usually a
    parameter, often called 'elements', 'choices', 'nodes'..., that
    must be provided as a sequence describing the various
    lines/items/nodes/... that can be highlighted in the widget. When
    'item_help=True' is passed, every element of this sequence must
    be completed with a string which is the item-help string of the
    element (dialog(1) terminology). For instance, the following call
    with no inline per-item help support:

      code, t = d.checklist(
                    "<text>", height=0, width=0, list_height=0,
                    choices=[ ("Tag 1", "Item 1", False),
                              ("Tag 2", "Item 2", True),
                              ("Tag 3", "Item 3", True) ],
                    help_button=True)

    can be altered this way to provide inline item-specific help:

      code, t = d.checklist(
                    "<text>", height=0, width=0, list_height=0,
                    choices=[ ("Tag 1", "Item 1", False, "Help 1"),
                              ("Tag 2", "Item 2", True,  "Help 2"),
                              ("Tag 3", "Item 3", True,  "Help 3") ],
                    help_button=True, item_help=True, help_tags=True)

    With this modification, the item-help string for the highlighted
    item is displayed in the bottom line of the screen and updated as
    the user highlights other items.

    If you don't want a Help button, just use 'item_help=True'
    without 'help_button=True' ('help_tags' doesn't matter). Then,
    you have the inline help at the bottom of the screen, and the
    following discussion about the return value can be ignored.

    If the user chooses the Help button, 'code' will be equal to
    Dialog.HELP ("help") and 't' will contain the tag string
    corresponding to the highlighted item when the Help button was
    pressed ("Tag 1/2/3" in the example). This is because of the
    'help_tags' option; without it (or with 'help_tags=False'), 't'
    would have contained the item-help string of the highlighted
    choice ("Help 1/2/3" in the example).

    If you remember what was said earlier, if 'item_help=True' had
    not been used in the previous example, 't' would still contain
    the tag of the highlighted choice if the user closed the widget
    with the Help button. This is the same as when using
    'item_help=True' in combination with 'help_tags=True'; however,
    you would get the item-help string instead if 'help_tags' were
    False (which is the default, as in the dialog backend, and in
    order to preserve compatibility with the 'menu' implementation
    that is several years old).

    Therefore, I recommend for consistency to use 'help_tags=True'
    whenever possible when specifying 'item_help=True'. This makes
    "--help-tags" a good candidate for use with
    Dialog.add_persistent_args() to avoid repeating it over and over.
    However, there are two cases where 'help_tags=True' cannot be
    used:
      - when the version of the dialog backend is lower than
        1.2-20130902 (the --help-tags option was added in this
        version);
      - when using empty or otherwise identical tags for presentation
        purposes (unless you don't need to tell which element was
        highlighted when the Help button was pressed, in which case
        it doesn't matter to be unable to discriminate between the
        tags).

    Getting the widget status before the Help button was pressed
    ------------------------------------------------------------
    Typically, when the user chooses Help in a widget, the
    application will display a dialog box such as 'textbox', 'msgbox'
    or 'scrollbox' and redisplay the original widget afterwards. For
    simple widgets such as 'inputbox', when the Dialog exit code is
    equal to Dialog.HELP, the return value contains enough
    information to redisplay the widget in the same state it had when
    Help was chosen. However, for more complex widgets such as
    'radiolist', 'checklist', 'form' and its derivatives, knowing the
    highlighted item is not enough to restore the widget state after
    processing the help request: one needs to know the checked item /
    list of checked items / form contents.

    This is where the 'help_status' keyword argument becomes useful.
    Example:

      code, t = d.checklist(
                    "<text>", height=0, width=0, list_height=0,
                    choices=[ ("Tag 1", "Item 1", False),
                              ("Tag 2", "Item 2", True),
                              ("Tag 3", "Item 3", True) ],
                    help_button=True, help_status=True)

    When Help is chosen, code == Dialog.HELP and 't' is a tuple of the
    form (tag, selected_tags, choices) where:
      - 'tag' gives the tag string of the highlighted item (which
        would be the value of 't' if 'help_status' were set to
        False);
      - 'selected_tags' is the... list of selected tags (note that
        highlighting and selecting an item are different things!);
      - 'choices' is a list built from the original 'choices'
        argument of the 'checklist' call and from the list of
        selected tags, that can be used as is to create a widget with
        the same items and selection state as the original widget had
        when Help was chosen.

    Normally, pythondialog should always provide something similar to
    the last item in the previous example in order to make it as easy
    as possible to redisplay the widget in the appropriate state. To
    know precisely what is returned with 'help_status=True', the best
    ways are usually to experiment or read the code (by the way,
    there are many examples of widgets with various combinations of
    'help_button', 'item_help' and 'help_status' in the demo).

    As can be inferred from the last sentence, the various options
    related to help support are not mutually exclusive and may be
    used together to provide good help support.

    It is also worth noting that the docstrings of the various
    widgets are written, in most cases, under the assumption that the
    widget was closed "normally" (typically, with the OK or Extra
    button). For instance, a docstring may state that the method
    returns a tuple of the form (code, tag) where 'tag' is ..., but
    actually, if using 'item_help=True' with 'help_tags=False', the
    'tag' may very well be an item-help string, and if using
    'help_status=True', it is likely to be a structured object such
    as a tuple or list. Of course, handling all these possible
    variations for all widgets would be a tedious task and would
    probably significantly degrade the readability of said
    docstrings.

    Checking the backend version
    ============================

    The Dialog constructor retrieves the version string of the dialog
    backend and stores it as an instance of a BackendVersion subclass
    into the 'cached_backend_version' attribute. This allows doing
    things such as ('d' being a Dialog instance):

      if d.compat == "dialog" and \\
        d.cached_backend_version >= DialogBackendVersion("1.2-20130902"):
          ...

    in a reliable way, allowing to fix the parsing and comparison
    algorithms right in the appropriate BackendVersion subclass,
    should the dialog-like backend versioning scheme change in
    unforeseen ways.

    As Xdialog seems to be dead and not to support --print-version,
    the 'cached_backend_version' attribute is set to None in
    Xdialog-compatibility mode (2013-09-12). Should this ever change,
    one should define an XDialogBackendVersion class to handle the
    particularities of the Xdialog versioning scheme.


    Exceptions
    ==========

    Please refer to the specific methods' docstrings or simply to the
    module's docstring for a list of all exceptions that might be
    raised by this class' methods.

    """
    try:
        _print_maxsize_cre = re.compile(r"""^MaxSize:[ \t]+
                                            (?P<rows>\d+),[ \t]*
                                            (?P<columns>\d+)[ \t]*$""",
                                        re.VERBOSE)
        _print_version_cre = re.compile(
            r"^Version:[ \t]+(?P<version>.+?)[ \t]*$", re.MULTILINE)
    except re.error, e:
        raise PythonDialogReModuleError(unicode(e))

    # DIALOG_OK, DIALOG_CANCEL, etc. are environment variables controlling
    # the dialog backend exit status in the corresponding situation ("low-level
    # exit status/code").
    #
    # Note:
    #    - 127 must not be used for any of the DIALOG_* values. It is used
    #      when a failure occurs in the child process before it exec()s
    #      dialog (where "before" includes a potential exec() failure).
    #    - 126 is also used (although in presumably rare situations).
    _DIALOG_OK        = 0
    _DIALOG_CANCEL    = 1
    _DIALOG_ESC       = 2
    _DIALOG_ERROR     = 3
    _DIALOG_EXTRA     = 4
    _DIALOG_HELP      = 5
    _DIALOG_ITEM_HELP = 6
    # cf. also _lowlevel_exit_codes and _dialog_exit_code_ll_to_hl which are
    # created by __init__(). It is not practical to define everything here,
    # because there is no equivalent of 'self' for the class outside method
    # definitions.
    _lowlevel_exit_code_varnames = frozenset(("OK", "CANCEL", "ESC", "ERROR",
                                              "EXTRA", "HELP", "ITEM_HELP"))

    # High-level exit codes, AKA "Dialog exit codes". These are the codes that
    # pythondialog-based applications should use.
    OK     = "ok"
    CANCEL = "cancel"
    ESC    = "esc"
    EXTRA  = "extra"
    HELP   = "help"

    # Define properties to maintain backward-compatibility while warning about
    # the obsolete attributes (which used to refer to the low-level exit codes
    # in pythondialog 2.x).
    DIALOG_OK        = property(_obsolete_property("OK"),
                         doc="Obsolete property superseded by Dialog.OK")
    DIALOG_CANCEL    = property(_obsolete_property("CANCEL"),
                         doc="Obsolete property superseded by Dialog.CANCEL")
    DIALOG_ESC       = property(_obsolete_property("ESC"),
                         doc="Obsolete property superseded by Dialog.ESC")
    DIALOG_EXTRA     = property(_obsolete_property("EXTRA"),
                         doc="Obsolete property superseded by Dialog.EXTRA")
    DIALOG_HELP      = property(_obsolete_property("HELP"),
                         doc="Obsolete property superseded by Dialog.HELP")
    # We treat DIALOG_ITEM_HELP and DIALOG_HELP the same way in pythondialog,
    # since both indicate the same user action ("Help" button pressed).
    DIALOG_ITEM_HELP = property(_obsolete_property("ITEM_HELP",
                                                   replacement="HELP"),
                         doc="Obsolete property superseded by Dialog.HELP")

    @property
    def DIALOG_ERROR(self):
        warnings.warn("the DIALOG_ERROR attribute of Dialog instances is "
                      "obsolete. Since the corresponding exit status is "
                      "automatically translated into a DialogError exception, "
                      "users should not see nor need this attribute. If you "
                      "think you have a good reason to use it, please expose "
                      "your situation on the pythondialog mailing-list.",
                      DeprecationWarning)
        # There is no corresponding high-level code; and if the user *really*
        # wants to know the (integer) error exit status, here it is...
        return self._DIALOG_ERROR

    def __init__(self, dialog="dialog", DIALOGRC=None,
                 compat="dialog", use_stdout=None):
        """Constructor for Dialog instances.

        dialog     -- name of (or path to) the dialog-like program to
                      use; if it contains a '/', it is assumed to be
                      a path and is used as is; otherwise, it is
                      looked for according to the contents of the
                      PATH environment variable, which defaults to
                      ":/bin:/usr/bin" if unset.
        DIALOGRC --   string to pass to the dialog-like program as
                      the DIALOGRC environment variable, or None if
                      no modification to the environment regarding
                      this variable should be done in the call to the
                      dialog-like program
        compat     -- compatibility mode (see below)
        use_stdout -- read dialog's standard output stream instead of
                      its standard error stream in order to get
                      most 'results' (user-supplied strings, etc.;
                      basically everything apart from the exit
                      status). This is for compatibility with Xdialog
                      and should only be used if you have a good
                      reason to do so.


        The officially supported dialog-like program in pythondialog
        is the well-known dialog program written in C, based on the
        ncurses library. It is also known as cdialog and its home
        page is currently (2013-08-12) located at:

            http://invisible-island.net/dialog/dialog.html

        If you want to use a different program such as Xdialog, you
        should indicate the executable file name with the 'dialog'
        argument *and* the compatibility type that you think it
        conforms to with the 'compat' argument. Currently, 'compat'
        can be either "dialog" (for dialog; this is the default) or
        "Xdialog" (for, well, Xdialog).

        The 'compat' argument allows me to cope with minor
        differences in behaviour between the various programs
        implementing the dialog interface (not the text or graphical
        interface, I mean the "API"). However, having to support
        various APIs simultaneously is ugly and I would really prefer
        you to report bugs to the relevant maintainers when you find
        incompatibilities with dialog. This is for the benefit of
        pretty much everyone that relies on the dialog interface.

        Notable exceptions:

            ExecutableNotFound
            PythonDialogOSError
            UnableToRetrieveBackendVersion
            UnableToParseBackendVersion

        """
        # DIALOGRC differs from the Dialog._DIALOG_* attributes in that:
        #   1. It is an instance attribute instead of a class attribute.
        #   2. It should be a string if not None.
        #   3. We may very well want it to be unset.
        if DIALOGRC is not None:
            self.DIALOGRC = DIALOGRC

        # Mapping from "OK", "CANCEL", ... to the corresponding dialog exit
        # statuses (integers).
        self._lowlevel_exit_codes = dict((
            name, getattr(self, "_DIALOG_" + name))
            for name in self._lowlevel_exit_code_varnames)

        # Mapping from dialog exit status (integer) to Dialog exit code ("ok",
        # "cancel", ... strings referred to by Dialog.OK, Dialog.CANCEL, ...);
        # in other words, from low-level to high-level exit code.
        self._dialog_exit_code_ll_to_hl = {}
        for name in self._lowlevel_exit_code_varnames:
            intcode = self._lowlevel_exit_codes[name]

            if name == "ITEM_HELP":
                self._dialog_exit_code_ll_to_hl[intcode] = self.HELP
            elif name == "ERROR":
                continue
            else:
                self._dialog_exit_code_ll_to_hl[intcode] = getattr(self, name)

        self._dialog_prg = _path_to_executable(dialog)
        self.compat = compat
        self.dialog_persistent_arglist = []

        # Use stderr or stdout for reading dialog's output?
        if self.compat == "Xdialog":
            # Default to using stdout for Xdialog
            self.use_stdout = True
        else:
            self.use_stdout = False
        if use_stdout is not None:
            # Allow explicit setting
            self.use_stdout = use_stdout
        if self.use_stdout:
            self.add_persistent_args(["--stdout"])

        self.setup_debug(False)

        if compat == "dialog":
            self.cached_backend_version = DialogBackendVersion.fromstring(
                self.backend_version())
        else:
            # Xdialog doesn't seem to offer --print-version (2013-09-12)
            self.cached_backend_version = None

    @classmethod
    def dash_escape(cls, args):
        """Escape all elements of 'args' that need escaping.

        'args' may be any sequence and is not modified by this method.
        Return a new list where every element that needs escaping has
        been escaped.

        An element needs escaping when it starts with two ASCII hyphens
        ('--'). Escaping consists in prepending an element composed of
        two ASCII hyphens, i.e., the string '--'.

        All high-level Dialog methods automatically perform dash
        escaping where appropriate. In particular, this is the case
        for every method that provides a widget: yesno(), msgbox(),
        etc. You only need to do it yourself when calling a low-level
        method such as add_persistent_args().

        """
        return _dash_escape(args)

    @classmethod
    def dash_escape_nf(cls, args):
        """Escape all elements of 'args' that need escaping, except the first one.

        See dash_escape() for details. Return a new list.

        All high-level Dialog methods automatically perform dash
        escaping where appropriate. In particular, this is the case
        for every method that provides a widget: yesno(), msgbox(),
        etc. You only need to do it yourself when calling a low-level
        method such as add_persistent_args().

        """
        return _dash_escape_nf(args)

    def add_persistent_args(self, args):
        """Add arguments to use for every subsequent dialog call.

        This method cannot guess which elements of 'args' are dialog
        options (such as '--title') and which are not (for instance,
        you might want to use '--title' or even '--' as an argument
        to a dialog option). Therefore, this method does not perform
        any kind of dash escaping; you have to do it yourself.
        dash_escape() and dash_escape_nf() may be useful for this
        purpose.

        """
        self.dialog_persistent_arglist.extend(args)

    def set_background_title(self, text):
        """Set the background title for dialog.

        text   -- string to use as the background title

        """
        self.add_persistent_args(self.dash_escape_nf(("--backtitle", text)))

    # For compatibility with the old dialog
    def setBackgroundTitle(self, text):
        """Set the background title for dialog.

        text   -- string to use as the background title

        This method is obsolete. Please remove calls to it from your
        programs.

        """
        warnings.warn("Dialog.setBackgroundTitle() has been obsolete for "
                      "many years; use Dialog.set_background_title() instead",
                      DeprecationWarning)
        self.set_background_title(text)

    def setup_debug(self, enable, file=None, always_flush=False):
        """Setup the debugging parameters.

        When enabled, all dialog commands are written to 'file' using
        Bourne shell syntax.

        enable         -- boolean indicating whether to enable or
                          disable debugging
        file           -- file object where to write debugging
                          information
        always_flush   -- boolean indicating whether to call
                          file.flush() after each command written

        """
        self._debug_enabled = enable

        if not hasattr(self, "_debug_logfile"):
            self._debug_logfile = None
        # Allows to switch debugging on and off without having to pass the file
        # object again and again.
        if file is not None:
            self._debug_logfile = file

        if enable and self._debug_logfile is None:
            raise BadPythonDialogUsage(
                "you must specify a file object when turning debugging on")

        self._debug_always_flush = always_flush
        self._debug_first_output = True

    def _write_command_to_file(self, env, arglist):
        envvar_settings_list = []

        if "DIALOGRC" in env:
            envvar_settings_list.append(
                "DIALOGRC={0}".format(_shell_quote(env["DIALOGRC"])))

        for var in self._lowlevel_exit_code_varnames:
            varname = "DIALOG_" + var
            envvar_settings_list.append(
                "{0}={1}".format(varname, _shell_quote(env[varname])))

        command_str = ' '.join(envvar_settings_list +
                               list(imap(_shell_quote, arglist)))
        s = "{separator}{cmd}\n\nArgs: {args!r}\n".format(
            separator="" if self._debug_first_output else ("-" * 79) + "\n",
            cmd=command_str, args=arglist)

        self._debug_logfile.write(s)
        if self._debug_always_flush:
            self._debug_logfile.flush()

        self._debug_first_output = False

    def _call_program(self, cmdargs, **kwargs):
        """Do the actual work of invoking the dialog-like program.

        Communication with the dialog-like program is performed
        through one pipe(2) and optionally a user-specified file
        descriptor, depending on 'redir_child_stdin_from_fd'. The
        pipe allows the parent process to read what dialog writes on
        its standard error[*] stream.

        If 'use_persistent_args' is True (the default), the elements
        of self.dialog_persistent_arglist are passed as the first
        arguments to self._dialog_prg; otherwise,
        self.dialog_persistent_arglist is not used at all. The
        remaining arguments are those computed from kwargs followed
        by the elements of 'cmdargs'.

        If 'dash_escape' is the string "non-first", then every
        element of 'cmdargs' that starts with '--' is escaped by
        prepending an element consisting of '--', except the first
        one (which is usually a dialog option such as '--yesno').
        In order to disable this escaping mechanism, pass the string
        "none" as 'dash_escape'.

        If 'redir_child_stdin_from_fd' is not None, it should be an
        open file descriptor (i.e., an integer). That file descriptor
        will be connected to dialog's standard input. This is used by
        the gauge widget to feed data to dialog, as well as for
        progressbox() to allow dialog to read data from a
        possibly-growing file.

        If 'redir_child_stdin_from_fd' is None, the standard input in
        the child process (which runs dialog) is not redirected in
        any way.

        If 'close_fds' is passed, it should be a sequence of
        file descriptors that will be closed by the child process
        before it exec()s the dialog-like program.

          [*] standard ouput stream with 'use_stdout'

        Notable exception: PythonDialogOSError (if any of the pipe(2)
                           or close(2) system calls fails...)

        """
        if 'close_fds' in kwargs: close_fds = kwargs['close_fds']; del kwargs['close_fds']
        else: close_fds = ()
        if 'redir_child_stdin_from_fd' in kwargs: redir_child_stdin_from_fd = kwargs['redir_child_stdin_from_fd']; del kwargs['redir_child_stdin_from_fd']
        else: redir_child_stdin_from_fd = None
        if 'use_persistent_args' in kwargs: use_persistent_args = kwargs['use_persistent_args']; del kwargs['use_persistent_args']
        else: use_persistent_args = True
        if 'dash_escape' in kwargs: dash_escape = kwargs['dash_escape']; del kwargs['dash_escape']
        else: dash_escape = "non-first"

        # We want to define DIALOG_OK, DIALOG_CANCEL, etc. in the
        # environment of the child process so that we know (and
        # even control) the possible dialog exit statuses.
        new_environ = {}
        new_environ.update(os.environ)
        for var, value in self._lowlevel_exit_codes.items():
            varname = "DIALOG_" + var
            new_environ[varname] = unicode(value)
        if hasattr(self, "DIALOGRC"):
            new_environ["DIALOGRC"] = self.DIALOGRC

        if dash_escape == "non-first":
            # Escape all elements of 'cmdargs' that start with '--', except the
            # first one.
            cmdargs = self.dash_escape_nf(cmdargs)
        elif dash_escape != "none":
            raise PythonDialogBug("invalid value for 'dash_escape' parameter: "
                                  "{0!r}".format(dash_escape))

        arglist = [ self._dialog_prg ]

        if use_persistent_args:
            arglist.extend(self.dialog_persistent_arglist)

        arglist.extend(_compute_common_args(kwargs) + cmdargs)

        if self._debug_enabled:
            # Write the complete command line with environment variables
            # setting to the debug log file (Bourne shell syntax for easy
            # copy-pasting into a terminal, followed by repr(arglist)).
            self._write_command_to_file(new_environ, arglist)

        # Create a pipe so that the parent process can read dialog's
        # output on stderr (stdout with 'use_stdout')
        with _OSErrorHandling():
            # rfd = File Descriptor for Reading
            # wfd = File Descriptor for Writing
            (child_output_rfd, child_output_wfd) = os.pipe()

        child_pid = os.fork()
        if child_pid == 0:
            # We are in the child process. We MUST NOT raise any exception.
            try:
                # 1) If the write end of a pipe isn't closed, the read end
                #    will never see EOF, which can indefinitely block the
                #    child waiting for input. To avoid this, the write end
                #    must be closed in the father *and* child processes.
                # 2) The child process doesn't need child_output_rfd.
                for fd in close_fds + (child_output_rfd,):
                    os.close(fd)
                # We want:
                #   - to keep a reference to the father's stderr for error
                #     reporting (and use line-buffering for this stream);
                #   - dialog's output on stderr[*] to go to child_output_wfd;
                #   - data written to fd 'redir_child_stdin_from_fd'
                #     (if not None) to go to dialog's stdin.
                #
                #       [*] stdout with 'use_stdout'
                #
                # We'll just print the result of traceback.format_exc() to
                # father_stderr, which is a byte string in Python 2, hence the
                # binary mode.
                father_stderr = open(os.dup(2), mode="wb")
                os.dup2(child_output_wfd, 1 if self.use_stdout else 2)
                if redir_child_stdin_from_fd is not None:
                    os.dup2(redir_child_stdin_from_fd, 0)

                os.execve(self._dialog_prg, arglist, new_environ)
            except:
                print(traceback.format_exc(), file=father_stderr)
                father_stderr.close()
                os._exit(127)

            # Should not happen unless there is a bug in Python
            os._exit(126)

        # We are in the father process.
        #
        # It is essential to close child_output_wfd, otherwise we will never
        # see EOF while reading on child_output_rfd and the parent process
        # will block forever on the read() call.
        # [ after the fork(), the "reference count" of child_output_wfd from
        #   the operating system's point of view is 2; after the child exits,
        #   it is 1 until the father closes it itself; then it is 0 and a read
        #   on child_output_rfd encounters EOF once all the remaining data in
        #   the pipe has been read. ]
        with _OSErrorHandling():
            os.close(child_output_wfd)
        return (child_pid, child_output_rfd)

    def _wait_for_program_termination(self, child_pid, child_output_rfd):
        """Wait for a dialog-like process to terminate.

        This function waits for the specified process to terminate,
        raises the appropriate exceptions in case of abnormal
        termination and returns the Dialog exit code (high-level) and
        stderr[*] output of the process as a tuple:
        (hl_exit_code, output_string).

        'child_output_rfd' must be the file descriptor for the
        reading end of the pipe created by self._call_program(), the
        writing end of which was connected by self._call_program()
        to the child process's standard error[*].

        This function reads the process' output on standard error[*]
        from 'child_output_rfd' and closes this file descriptor once
        this is done.

          [*] actually, standard output if self.use_stdout is True

        Notable exceptions:

            DialogTerminatedBySignal
            DialogError
            PythonDialogErrorBeforeExecInChildProcess
            PythonDialogIOError    if the Python version is < 3.3
            PythonDialogOSError
            PythonDialogBug
            ProbablyPythonBug

        """
        # Read dialog's output on its stderr (stdout with 'use_stdout')
        with _OSErrorHandling():
            with open(child_output_rfd, "r") as f:
                child_output = f.read()
            # The closing of the file object causes the end of the pipe we used
            # to read dialog's output on its stderr to be closed too. This is
            # important, otherwise invoking dialog enough times would
            # eventually exhaust the maximum number of open file descriptors.

        exit_info = os.waitpid(child_pid, 0)[1]
        if os.WIFEXITED(exit_info):
            ll_exit_code = os.WEXITSTATUS(exit_info)
        # As we wait()ed for the child process to terminate, there is no
        # need to call os.WIFSTOPPED()
        elif os.WIFSIGNALED(exit_info):
            raise DialogTerminatedBySignal("the dialog-like program was "
                                           "terminated by signal %d" %
                                           os.WTERMSIG(exit_info))
        else:
            raise PythonDialogBug("please report this bug to the "
                                  "pythondialog maintainer(s)")

        if ll_exit_code == self._DIALOG_ERROR:
            raise DialogError(
                "the dialog-like program exited with status {0} (which was "
                "passed to it as the DIALOG_ERROR environment variable). "
                "Sometimes, the reason is simply that dialog was given a "
                "height or width parameter that is too big for the terminal "
                "in use. Its output, with leading and trailing whitespace "
                "stripped, was:\n\n{1}".format(ll_exit_code,
                                               child_output.strip()))
        elif ll_exit_code == 127:
            raise PythonDialogErrorBeforeExecInChildProcess(dedent("""\
            possible reasons include:
              - the dialog-like program could not be executed (this can happen
                for instance if the Python program is trying to call the
                dialog-like program with arguments that cannot be represented
                in the user's locale [LC_CTYPE]);
              - the system is out of memory;
              - the maximum number of open file descriptors has been reached;
              - a cosmic ray hit the system memory and flipped nasty bits.
            There ought to be a traceback above this message that describes
            more precisely what happened."""))
        elif ll_exit_code == 126:
            raise ProbablyPythonBug(
                "a child process returned with exit status 126; this might "
                "be the exit status of the dialog-like program, for some "
                "unknown reason (-> probably a bug in the dialog-like "
                "program); otherwise, we have probably found a python bug")

        try:
            hl_exit_code = self._dialog_exit_code_ll_to_hl[ll_exit_code]
        except KeyError:
            raise PythonDialogBug(
                "unexpected low-level exit status (new code?): {0!r}".format(
                    ll_exit_code))

        return (hl_exit_code, child_output)

    def _perform(self, cmdargs, **kwargs):
        """Perform a complete dialog-like program invocation.

        This function invokes the dialog-like program, waits for its
        termination and returns the appropriate Dialog exit code
        (high-level) along with whatever output it produced.

        See _call_program() for a description of the parameters.

        Notable exceptions:

            any exception raised by self._call_program() or
            self._wait_for_program_termination()

        """
        if 'use_persistent_args' in kwargs: use_persistent_args = kwargs['use_persistent_args']; del kwargs['use_persistent_args']
        else: use_persistent_args = True
        if 'dash_escape' in kwargs: dash_escape = kwargs['dash_escape']; del kwargs['dash_escape']
        else: dash_escape = "non-first"

        (child_pid, child_output_rfd) = \
                    self._call_program(cmdargs, dash_escape=dash_escape,
                                       use_persistent_args=use_persistent_args,
                                       **kwargs)
        (exit_code, output) = \
                    self._wait_for_program_termination(child_pid,
                                                       child_output_rfd)
        return (exit_code, output)

    def _strip_xdialog_newline(self, output):
        """Remove trailing newline (if any) in Xdialog compatibility mode"""
        if self.compat == "Xdialog" and output.endswith("\n"):
            output = output[:-1]
        return output

    # This is for compatibility with the old dialog.py
    def _perform_no_options(self, cmd):
        """Call dialog without passing any more options."""

        warnings.warn("Dialog._perform_no_options() has been obsolete for "
                      "many years", DeprecationWarning)
        return os.system(self._dialog_prg + ' ' + cmd)

    # For compatibility with the old dialog.py
    def clear(self):
        """Clear the screen. Equivalent to the dialog --clear option.

        This method is obsolete. Please remove calls to it from your
        programs. You may use the clear(1) program to clear the screen.
        cf. clear_screen() in demo.py for an example.

        """
        warnings.warn("Dialog.clear() has been obsolete for many years.\n"
                      "You may use the clear(1) program to clear the screen.\n"
                      "cf. clear_screen() in demo.py for an example",
                      DeprecationWarning)
        self._perform_no_options('--clear')

    def _help_status_on(self, kwargs):
        return ("--help-status" in self.dialog_persistent_arglist
                or kwargs.get("help_status", False))

    def _parse_quoted_string(self, s, start=0):
        """Parse a quoted string from a dialog help output."""
        if start >= len(s) or s[start] != '"':
            raise PythonDialogBug("quoted string does not start with a double "
                                  "quote: {0!r}".format(s))

        l = []
        i = start + 1

        while i < len(s) and s[i] != '"':
            if s[i] == "\\":
                i += 1
                if i >= len(s):
                    raise PythonDialogBug(
                        "quoted string ends with a backslash: {0!r}".format(s))
            l.append(s[i])
            i += 1

        if s[i] != '"':
            raise PythonDialogBug("quoted string does not and with a double "
                                  "quote: {0!r}".format(s))

        return (''.join(l), i+1)

    def _split_shellstyle_arglist(self, s):
        """Split an argument list with shell-style quoting performed by dialog.

        Any argument in 's' may or may not be quoted. Quoted
        arguments are always expected to be enclosed in double quotes
        (more restrictive than what the POSIX shell allows).

        This function could maybe be replaced with shlex.split(),
        however:
          - shlex only handles Unicode strings in Python 2.7.3 and
            above;
          - the bulk of the work is done by _parse_quoted_string(),
            which is probably still needed in _parse_help(), where
            one needs to parse things such as 'HELP <id> <status>' in
            which <id> may be quoted but <status> is never quoted,
            even if it contains spaces or quotes.

        """
        s = s.rstrip()
        l = []
        i = 0

        while i < len(s):
            if s[i] == '"':
                arg, i = self._parse_quoted_string(s, start=i)
                if i < len(s) and s[i] != ' ':
                    raise PythonDialogBug(
                        "expected a space or end-of-string after quoted "
                        "string in {0!r}, but found {1!r}".format(s, s[i]))
                # Start of the next argument, or after the end of the string
                i += 1
                l.append(arg)
            else:
                try:
                    end = s.index(' ', i)
                except ValueError:
                    end = len(s)

                l.append(s[i:end])
                # Start of the next argument, or after the end of the string
                i = end + 1

        return l

    def _parse_help(self, output, kwargs, **_3to2kwargs):
        """Parse the dialog help output from a widget.

        'kwargs' should contain the keyword arguments used in the
        widget call that produced the help output.

        'multival' is for widgets that return a list of values as
        opposed to a single value.

        'raw_format' is for widgets that don't start their help
        output with the string "HELP ".

        """
        if 'raw_format' in _3to2kwargs: raw_format = _3to2kwargs['raw_format']; del _3to2kwargs['raw_format']
        else: raw_format = False
        if 'multival_on_single_line' in _3to2kwargs: multival_on_single_line = _3to2kwargs['multival_on_single_line']; del _3to2kwargs['multival_on_single_line']
        else: multival_on_single_line = False
        if 'multival' in _3to2kwargs: multival = _3to2kwargs['multival']; del _3to2kwargs['multival']
        else: multival = False

        l = output.splitlines()

        if raw_format:
            # This format of the help output is either empty or consists of
            # only one line (possibly terminated with \n). It is
            # encountered with --calendar and --inputbox, among others.
            if len(l) > 1:
                raise PythonDialogBug("raw help feedback unexpected as "
                                      "multiline: {0!r}".format(output))
            elif len(l) == 0:
                return ""
            else:
                return l[0]

        # Simple widgets such as 'yesno' will fall in this case if they use
        # this method.
        if not l:
            return None

        # The widgets that actually use --help-status always have the first
        # help line indicating the active item; there is no risk of
        # confusing this line with the first line produced by --help-status.
        if not l[0].startswith("HELP "):
            raise PythonDialogBug(
                "unexpected help output that does not start with 'HELP ': "
                "{0!r}".format(output))

        # Everything that follows "HELP "; what it contains depends on whether
        # --item-help and/or --help-tags were passed to dialog.
        s = l[0][5:]

        if not self._help_status_on(kwargs):
            return s

        if multival:
            if multival_on_single_line:
                args = self._split_shellstyle_arglist(s)
                if not args:
                    raise PythonDialogBug(
                        "expected a non-empty space-separated list of "
                        "possibly-quoted strings in this help output: {0!r}"
                        .format(output))
                return (args[0], args[1:])
            else:
                return (s, l[1:])
        else:
            if not s:
                raise PythonDialogBug(
                    "unexpected help output whose first line is 'HELP '")
            elif s[0] != '"':
                l2 = s.split(' ', 1)
                if len(l2) == 1:
                    raise PythonDialogBug(
                        "expected 'HELP <id> <status>' in the help output, "
                        "but couldn't find any space after 'HELP '")
                else:
                    return tuple(l2)
            else:
                help_id, after_index = self._parse_quoted_string(s)
                if not s[after_index:].startswith(" "):
                    raise PythonDialogBug(
                        "expected 'HELP <quoted_id> <status>' in the help "
                        "output, but couldn't find any space after "
                        "'HELP <quoted_id>'")
                return (help_id, s[after_index+1:])

    def _widget_with_string_output(self, args, kwargs,
                                   strip_xdialog_newline=False,
                                   raw_help=False):
        """Generic implementation for a widget that produces a single string.

        The help output must be present regardless of whether
        --help-status was passed or not.

        """
        code, output = self._perform(args, **kwargs)

        if strip_xdialog_newline:
            output = self._strip_xdialog_newline(output)

        if code == self.HELP:
            # No check for --help-status
            help_data = self._parse_help(output, kwargs, raw_format=raw_help)
            return (code, help_data)
        else:
            return (code, output)

    def _widget_with_no_output(self, widget_name, args, kwargs):
        """Generic implementation for a widget that produces no output."""
        code, output = self._perform(args, **kwargs)

        if output:
            raise PythonDialogBug(
                "expected an empty output from {0!r}, but got: {1!r}".format(
                    widget_name, output))

        return code

    def _dialog_version_check(self, version_string, feature):
        if self.compat == "dialog":
            minimum_version = DialogBackendVersion.fromstring(version_string)

            if self.cached_backend_version < minimum_version:
                raise InadequateBackendVersion(
                    "the programbox widget requires dialog {0} or later, "
                    "but you seem to be using version {1}".format(
                        minimum_version, self.cached_backend_version))

    def backend_version(self):
        """Get the version of the dialog-like program (backend).

        If the version of the dialog-like program can be retrieved,
        return it as a string; otherwise, raise
        UnableToRetrieveBackendVersion.

        This version is not to be confused with the pythondialog
        version.

        In most cases, you should rather use the
        'cached_backend_version' attribute of Dialog instances,
        because:
          - it avoids calling the backend every time one needs the
            version;
          - it is a BackendVersion instance (or instance of a
            subclass) that allows easy and reliable comparisons
            between versions;
          - the version string corresponding to a BackendVersion
            instance (or instance of a subclass) can be obtained with
            unicode().

        Notable exceptions:

            UnableToRetrieveBackendVersion
            PythonDialogReModuleError
            any exception raised by self._perform()

        """
        code, output = self._perform(["--print-version"],
                                     use_persistent_args=False)
        if code == self.OK:
            try:
                mo = self._print_version_cre.match(output)
                if mo:
                    return mo.group("version")
                else:
                    raise UnableToRetrieveBackendVersion(
                        "unable to parse the output of '{0} --print-version': "
                        "{1!r}".format(self._dialog_prg, output))
            except re.error, e:
                raise PythonDialogReModuleError(unicode(e))
        else:
            raise UnableToRetrieveBackendVersion(
                "exit code {0!r} from the backend".format(code))

    def maxsize(self, **kwargs):
        """Get the maximum size of dialog boxes.

        If the exit code from the backend is self.OK, return a
        (lines, cols) tuple of integers; otherwise, return None.

        If you want to obtain the number of lines and columns of the
        terminal, you should call this method with
        use_persistent_args=False, because arguments such as
        --backtitle modify the values returned.

        Notable exceptions:

            PythonDialogReModuleError
            any exception raised by self._perform()

        """
        code, output = self._perform(["--print-maxsize"], **kwargs)
        if code == self.OK:
            try:
                mo = self._print_maxsize_cre.match(output)
                if mo:
                    return tuple(imap(int, mo.group("rows", "columns")))
                else:
                    raise PythonDialogBug(
                        "Unable to parse the output of '{0} --print-maxsize': "
                        "{1!r}".format(self._dialog_prg, output))
            except re.error, e:
                raise PythonDialogReModuleError(unicode(e))
        else:
            return None

    @widget
    def buildlist(self, text, height=0, width=0, list_height=0, items=[],
                  **kwargs):
        """Display a buildlist box.

        text        -- text to display in the box
        height      -- height of the box
        width       -- width of the box
        list_height -- height of the selected and unselected list
                       boxes
        items       -- a list of (tag, item, status) tuples where
                       'status' specifies the initial
                       selected/unselected state of each entry; can
                       be True or False, 1 or 0, "on" or "off" (True,
                       1 and "on" meaning selected), or any case
                       variation of these two strings.

        A buildlist dialog is similar in logic to the checklist but
        differs in presentation. In this widget, two lists are
        displayed, side by side. The list on the left shows
        unselected items. The list on the right shows selected items.
        As items are selected or unselected, they move between the
        two lists. The 'status' component of 'items' specifies which
        items are initially selected.

        Return a tuple of the form (code, tags) where:
          - 'code' is the Dialog exit code;
          - 'tags' is a list of the tags corresponding to the
            selected items, in the order they have in the list on the
            right.

        Keys: SPACE   select or deselect the highlighted item, i.e.,
                      move it between the left and right lists
              ^       move the focus to the left list
              $       move the focus to the right list
              TAB     move focus (see 'visit_items' below)
              ENTER   press the focused button

        If called with 'visit_items=True', the TAB key can move the
        focus to the left and right lists, which is probably more
        intuitive for users than the default behavior that requires
        using ^ and $ for this purpose.

        This widget requires dialog >= 1.2 (2012-12-30).

        Notable exceptions:

            any exception raised by self._perform() or _to_onoff()

        """
        self._dialog_version_check("1.2", "the buildlist widget")

        cmd = ["--buildlist", text, unicode(height), unicode(width), unicode(list_height)]
        for t in items:
            cmd.extend([ t[0], t[1], _to_onoff(t[2]) ] + list(t[3:]))

        code, output = self._perform(cmd, **kwargs)

        if code == self.HELP:
            help_data = self._parse_help(output, kwargs, multival=True,
                                         multival_on_single_line=True)
            if self._help_status_on(kwargs):
                help_id, selected_tags = help_data

                updated_items = []
                for elt in items:
                    tag, item, status = elt[:3]
                    rest = elt[3:]
                    updated_items.append([ tag, item, tag in selected_tags ]
                                         + list(rest))
                return (code, (help_id, selected_tags, updated_items))
            else:
                return (code, help_data)
        elif code in (self.OK, self.EXTRA):
            return (code, self._split_shellstyle_arglist(output))
        else:
            return (code, None)

    def _calendar_parse_date(self, date_str):
        try:
            mo = _calendar_date_cre.match(date_str)
        except re.error, e:
            raise PythonDialogReModuleError(unicode(e))

        if not mo:
            raise UnexpectedDialogOutput(
                "the dialog-like program returned the following "
                "unexpected output (a date string was expected) from the "
                "calendar box: {0!r}".format(date_str))

        return [ int(s) for s in mo.group("day", "month", "year") ]

    @widget
    def calendar(self, text, height=6, width=0, day=0, month=0, year=0,
                 **kwargs):
        """Display a calendar dialog box.

        text   -- text to display in the box
        height -- height of the box (minus the calendar height)
        width  -- width of the box
        day    -- inititial day highlighted
        month  -- inititial month displayed
        year   -- inititial year selected (0 causes the current date
                  to be used as the initial date)

        A calendar box displays month, day and year in separately
        adjustable windows. If the values for day, month or year are
        missing or negative, the current date's corresponding values
        are used. You can increment or decrement any of those using
        the left, up, right and down arrows. Use tab or backtab to
        move between windows. If the year is given as zero, the
        current date is used as an initial value.

        Return a tuple of the form (code, date) where:
          - 'code' is the Dialog exit code;
          - 'date' is a list of the form [day, month, year], where
            'day', 'month' and 'year' are integers corresponding to
            the date chosen by the user.

        Notable exceptions:
            - any exception raised by self._perform()
            - UnexpectedDialogOutput
            - PythonDialogReModuleError

        """
        (code, output) = self._perform(
            ["--calendar", text, unicode(height), unicode(width), unicode(day),
               unicode(month), unicode(year)],
            **kwargs)

        if code == self.HELP:
            # The output does not depend on whether --help-status was passed
            # (dialog 1.2-20130902).
            help_data = self._parse_help(output, kwargs, raw_format=True)
            return (code, self._calendar_parse_date(help_data))
        elif code in (self.OK, self.EXTRA):
            return (code, self._calendar_parse_date(output))
        else:
            return (code, None)

    @widget
    def checklist(self, text, height=15, width=54, list_height=7,
                  choices=[], **kwargs):
        """Display a checklist box.

        text        -- text to display in the box
        height      -- height of the box
        width       -- width of the box
        list_height -- number of entries displayed in the box (which
                       can be scrolled) at a given time
        choices     -- a list of tuples (tag, item, status) where
                       'status' specifies the initial on/off state of
                       each entry; can be True or False, 1 or 0, "on"
                       or "off" (True, 1 and "on" meaning checked),
                       or any case variation of these two strings.

        Return a tuple of the form (code, [tag, ...]) with the tags
        for the entries that were selected by the user. 'code' is the
        Dialog exit code.

        If the user exits with ESC or CANCEL, the returned tag list
        is empty.

        Notable exceptions:

            any exception raised by self._perform() or _to_onoff()

        """
        cmd = ["--checklist", text, unicode(height), unicode(width), unicode(list_height)]
        for t in choices:
            t = [ t[0], t[1], _to_onoff(t[2]) ] + list(t[3:])
            cmd.extend(t)

        # The dialog output cannot be parsed reliably (at least in dialog
        # 0.9b-20040301) without --separate-output (because double quotes in
        # tags are escaped with backslashes, but backslashes are not
        # themselves escaped and you have a problem when a tag ends with a
        # backslash--the output makes you think you've encountered an embedded
        # double-quote).
        kwargs["separate_output"] = True

        (code, output) = self._perform(cmd, **kwargs)
        # Since we used --separate-output, the tags are separated by a newline
        # in the output. There is also a final newline after the last tag.

        if code == self.HELP:
            help_data = self._parse_help(output, kwargs, multival=True)
            if self._help_status_on(kwargs):
                help_id, selected_tags = help_data

                updated_choices = []
                for elt in choices:
                    tag, item, status = elt[:3]
                    rest = elt[3:]
                    updated_choices.append([ tag, item, tag in selected_tags ]
                                           + list(rest))

                return (code, (help_id, selected_tags, updated_choices))
            else:
                return (code, help_data)
        else:
            return (code, output.split('\n')[:-1])

    def _form_updated_items(self, status, elements):
        """Return a complete list with up-to-date items from 'status'.

        Return a new list of same length as 'elements'. Items are
        taken from 'status', except when data inside 'elements'
        indicates a read-only field: such items are not output by
        dialog ... --help-status ..., and therefore have to be
        extracted from 'elements' instead of 'status'.

        Actually, for 'mixedform', the elements that are defined as
        read-only using the attribute instead of a non-positive
        field_length are not concerned by this function, since they
        are included in the --help-status output.

        """
        res = []
        for i, elt in enumerate(elements):
            label, yl, xl, item, yi, xi, field_length = elt[:7]
            res.append(status[i] if field_length > 0 else item)

        return res

    def _generic_form(self, widget_name, method_name, text, elements, height=0,
                      width=0, form_height=0, **kwargs):
        cmd = ["--%s" % widget_name, text, unicode(height), unicode(width),
               unicode(form_height)]

        if not elements:
            raise BadPythonDialogUsage(
                "{0}.{1}.{2}: empty ELEMENTS sequence: {3!r}".format(
                    __name__, type(self).__name__, method_name, elements))

        elt_len = len(elements[0]) # for consistency checking
        for i, elt in enumerate(elements):
            if len(elt) != elt_len:
                raise BadPythonDialogUsage(
                    "{0}.{1}.{2}: ELEMENTS[0] has length {3}, whereas "
                    "ELEMENTS[{4}] has length {5}".format(
                        __name__, type(self).__name__, method_name,
                        elt_len, i, len(elt)))

            # Give names to make the code more readable
            if widget_name in ("form", "passwordform"):
                label, yl, xl, item, yi, xi, field_length, input_length = \
                    elt[:8]
                rest = elt[8:]  # optional "item_help" string
            elif widget_name == "mixedform":
                label, yl, xl, item, yi, xi, field_length, input_length, \
                    attributes = elt[:9]
                rest = elt[9:]  # optional "item_help" string
            else:
                raise PythonDialogBug(
                    "unexpected widget name in {0}.{1}._generic_form(): "
                    "{2!r}".format(__name__, type(self).__name__, widget_name))

            for name, value in (("LABEL", label), ("ITEM", item)):
                if not isinstance(value, basestring):
                    raise BadPythonDialogUsage(
                        "{0}.{1}.{2}: {3} element not a string: {4!r}".format(
                            __name__, type(self).__name__,
                            method_name, name, value))

            cmd.extend((label, unicode(yl), unicode(xl), item, unicode(yi), unicode(xi),
                        unicode(field_length), unicode(input_length)))
            if widget_name == "mixedform":
                cmd.append(unicode(attributes))
            # "item help" string when using --item-help, nothing otherwise
            cmd.extend(rest)

        (code, output) = self._perform(cmd, **kwargs)

        if code == self.HELP:
            help_data = self._parse_help(output, kwargs, multival=True)
            if self._help_status_on(kwargs):
                help_id, status = help_data
                # 'status' does not contain the fields marked as read-only in
                # 'elements'. Build a list containing all up-to-date items.
                updated_items = self._form_updated_items(status, elements)

                # Reconstruct 'elements' with the updated items taken from
                # 'status'.
                updated_elements = []
                for elt, updated_item in izip(elements, updated_items):
                    label, yl, xl, item = elt[:4]
                    rest = elt[4:]
                    updated_elements.append([ label, yl, xl, updated_item ]
                                            + list(rest))
                return (code, (help_id, status, updated_elements))
            else:
                return (code, help_data)
        else:
            return (code, output.split('\n')[:-1])

    @widget
    def form(self, text, elements, height=0, width=0, form_height=0, **kwargs):
        """Display a form consisting of labels and fields.

        text        -- text to display in the box
        elements    -- sequence describing the labels and fields (see
                       below)
        height      -- height of the box
        width       -- width of the box
        form_height -- number of form lines displayed at the same time

        A form box consists in a series of fields and associated
        labels. This type of dialog is suitable for adjusting
        configuration parameters and similar tasks.

        Each element of 'elements' must itself be a sequence
        (LABEL, YL, XL, ITEM, YI, XI, FIELD_LENGTH, INPUT_LENGTH)
        containing the various parameters concerning a given field
        and the associated label.

        LABEL is a string that will be displayed at row YL, column
        XL. ITEM is a string giving the initial value for the field,
        which will be displayed at row YI, column XI (row and column
        numbers starting from 1).

        FIELD_LENGTH and INPUT_LENGTH are integers that respectively
        specify the number of characters used for displaying the
        field and the maximum number of characters that can be
        entered for this field. These two integers also determine
        whether the contents of the field can be modified, as
        follows:

          - if FIELD_LENGTH is zero, the field cannot be altered and
            its contents determines the displayed length;

          - if FIELD_LENGTH is negative, the field cannot be altered
            and the opposite of FIELD_LENGTH gives the displayed
            length;

          - if INPUT_LENGTH is zero, it is set to FIELD_LENGTH.

        Return a tuple of the form (code, list) where 'code' is the
        Dialog exit code and 'list' gives the contents of every
        editable field on exit, with the same order as in 'elements'.

        Notable exceptions:

            BadPythonDialogUsage
            any exception raised by self._perform()

        """
        return self._generic_form("form", "form", text, elements,
                                  height, width, form_height, **kwargs)

    @widget
    def passwordform(self, text, elements, height=0, width=0, form_height=0,
                     **kwargs):
        """Display a form consisting of labels and invisible fields.

        This widget is identical to the form box, except that all
        text fields are treated as passwordbox widgets rather than
        inputbox widgets.

        By default (as in dialog), nothing is echoed to the terminal
        as the user types in the invisible fields. This can be
        confusing to users. Use the 'insecure' keyword argument if
        you want an asterisk to be echoed for each character entered
        by the user.

        Notable exceptions:

            BadPythonDialogUsage
            any exception raised by self._perform()

        """
        return self._generic_form("passwordform", "passwordform", text,
                                  elements, height, width, form_height,
                                  **kwargs)

    @widget
    def mixedform(self, text, elements, height=0, width=0, form_height=0,
                  **kwargs):
        """Display a form consisting of labels and fields.

        text        -- text to display in the box
        elements    -- sequence describing the labels and fields (see
                       below)
        height      -- height of the box
        width       -- width of the box
        form_height -- number of form lines displayed at the same time

        A mixedform box is very similar to a form box, and differs
        from the latter by allowing field attributes to be specified.

        Each element of 'elements' must itself be a sequence (LABEL,
        YL, XL, ITEM, YI, XI, FIELD_LENGTH, INPUT_LENGTH, ATTRIBUTES)
        containing the various parameters concerning a given field
        and the associated label.

        ATTRIBUTES is a bit mask with the following meaning:

          bit 0  -- the field should be hidden (e.g., a password)
          bit 1  -- the field should be read-only (e.g., a label)

        For all other parameters, please refer to the documentation
        of the form box.

        The return value is the same as would be with the form box,
        except that field marked as read-only with bit 1 of
        ATTRIBUTES are also included in the output list.

        Notable exceptions:

            BadPythonDialogUsage
            any exception raised by self._perform()

        """
        return self._generic_form("mixedform", "mixedform", text, elements,
                                  height, width, form_height, **kwargs)

    @widget
    def dselect(self, filepath, height=0, width=0, **kwargs):
        """Display a directory selection dialog box.

        filepath -- initial path
        height   -- height of the box
        width    -- width of the box

        The directory-selection dialog displays a text-entry window
        in which you can type a directory, and above that a window
        with directory names.

        Here, filepath can be a filepath in which case the directory
        window will display the contents of the path and the
        text-entry window will contain the preselected directory.

        Use tab or arrow keys to move between the windows. Within the
        directory window, use the up/down arrow keys to scroll the
        current selection. Use the space-bar to copy the current
        selection into the text-entry window.

        Typing any printable characters switches focus to the
        text-entry window, entering that character as well as
        scrolling the directory window to the closest match.

        Use a carriage return or the "OK" button to accept the
        current value in the text-entry window and exit.

        Return a tuple of the form (code, path) where 'code' is the
        Dialog exit code and 'path' is the directory chosen by the
        user.

        Notable exceptions:

            any exception raised by self._perform()

        """
        # The help output does not depend on whether --help-status was passed
        # (dialog 1.2-20130902).
        return self._widget_with_string_output(
            ["--dselect", filepath, unicode(height), unicode(width)],
            kwargs, raw_help=True)

    @widget
    def editbox(self, filepath, height=0, width=0, **kwargs):
        """Display a basic text editor dialog box.

        filepath -- file which determines the initial contents of
                    the dialog box
        height   -- height of the box
        width    -- width of the box

        The editbox dialog displays a copy of the file contents. You
        may edit it using the Backspace, Delete and cursor keys to
        correct typing errors. It also recognizes Page Up and Page
        Down. Unlike the inputbox, you must tab to the "OK" or
        "Cancel" buttons to close the dialog. Pressing the "Enter"
        key within the box will split the corresponding line.

        Return a tuple of the form (code, text) where 'code' is the
        Dialog exit code and 'text' is the contents of the text entry
        window on exit.

        Notable exceptions:

            any exception raised by self._perform()

        """
        return self._widget_with_string_output(
            ["--editbox", filepath, unicode(height), unicode(width)],
            kwargs)

    @widget
    def fselect(self, filepath, height=0, width=0, **kwargs):
        """Display a file selection dialog box.

        filepath -- initial file path
        height   -- height of the box
        width    -- width of the box

        The file-selection dialog displays a text-entry window in
        which you can type a filename (or directory), and above that
        two windows with directory names and filenames.

        Here, filepath can be a file path in which case the file and
        directory windows will display the contents of the path and
        the text-entry window will contain the preselected filename.

        Use tab or arrow keys to move between the windows. Within the
        directory or filename windows, use the up/down arrow keys to
        scroll the current selection. Use the space-bar to copy the
        current selection into the text-entry window.

        Typing any printable character switches focus to the
        text-entry window, entering that character as well as
        scrolling the directory and filename windows to the closest
        match.

        Use a carriage return or the "OK" button to accept the
        current value in the text-entry window, or the "Cancel"
        button to cancel.

        Return a tuple of the form (code, path) where 'code' is the
        Dialog exit code and 'path' is the path chosen by the user
        (the last element of which may be a directory or a file).

        Notable exceptions:

            any exception raised by self._perform()

        """
        # The help output does not depend on whether --help-status was passed
        # (dialog 1.2-20130902).
        return self._widget_with_string_output(
            ["--fselect", filepath, unicode(height), unicode(width)],
            kwargs, strip_xdialog_newline=True, raw_help=True)

    def gauge_start(self, text="", height=8, width=54, percent=0, **kwargs):
        """Display gauge box.

        text    -- text to display in the box
        height  -- height of the box
        width   -- width of the box
        percent -- initial percentage shown in the meter

        A gauge box displays a meter along the bottom of the box. The
        meter indicates a percentage.

        This function starts the dialog-like program telling it to
        display a gauge box with a text in it and an initial
        percentage in the meter.

        Return value: undefined.


        Gauge typical usage
        -------------------

        Gauge typical usage (assuming that 'd' is an instance of the
        Dialog class) looks like this:
            d.gauge_start()
            # do something
            d.gauge_update(10)       # 10% of the whole task is done
            # ...
            d.gauge_update(100, "any text here") # work is done
            exit_code = d.gauge_stop()           # cleanup actions


        Notable exceptions:
            - any exception raised by self._call_program()
            - PythonDialogOSError

        """
        with _OSErrorHandling():
            # We need a pipe to send data to the child (dialog) process's
            # stdin while it is running.
            # rfd = File Descriptor for Reading
            # wfd = File Descriptor for Writing
            (child_stdin_rfd, child_stdin_wfd)  = os.pipe()

            (child_pid, child_output_rfd) = self._call_program(
                ["--gauge", text, unicode(height), unicode(width), unicode(percent)],
                redir_child_stdin_from_fd=child_stdin_rfd,
                close_fds=(child_stdin_wfd,), **kwargs)

            # fork() is done. We don't need child_stdin_rfd in the father
            # process anymore.
            os.close(child_stdin_rfd)

            self._gauge_process = {
                "pid": child_pid,
                "stdin": open(child_stdin_wfd, "w"),
                "child_output_rfd": child_output_rfd
                }

    def gauge_update(self, percent, text="", update_text=False):
        """Update a running gauge box.

        percent     -- new percentage (integer) to show in the gauge
                       meter
        text        -- new text to optionally display in the box
        update_text -- boolean indicating whether to update the
                       text in the box

        This function updates the percentage shown by the meter of a
        running gauge box (meaning 'gauge_start' must have been
        called previously). If update_text is True, the text
        displayed in the box is also updated.

        See the 'gauge_start' function's documentation for
        information about how to use a gauge.

        Return value: undefined.

        Notable exception: PythonDialogIOError (PythonDialogOSError
                           from Python 3.3 onwards) can be raised if
                           there is an I/O error while writing to the
                           pipe used to talk to the dialog-like
                           program.

        """
        if not isinstance(percent, int):
            raise BadPythonDialogUsage(
                "the 'percent' argument of gauge_update() must be an integer, "
                "but {0!r} is not".format(percent))

        if update_text:
            gauge_data = "XXX\n{0}\n{1}\nXXX\n".format(percent, text)
        else:
            gauge_data = "{0}\n".format(percent)
        with _OSErrorHandling():
            self._gauge_process["stdin"].write(gauge_data)
            self._gauge_process["stdin"].flush()

    # For "compatibility" with the old dialog.py...
    def gauge_iterate(*args, **kwargs):
        warnings.warn("Dialog.gauge_iterate() has been obsolete for "
                      "many years", DeprecationWarning)
        gauge_update(*args, **kwargs)

    @widget
    @retval_is_code
    def gauge_stop(self):
        """Terminate a running gauge widget.

        This function performs the appropriate cleanup actions to
        terminate a running gauge (started with 'gauge_start').

        See the 'gauge_start' function's documentation for
        information about how to use a gauge.

        Return value: the Dialog exit code from the backend.

        Notable exceptions:
            - any exception raised by
              self._wait_for_program_termination()
            - PythonDialogIOError (PythonDialogOSError from
              Python 3.3 onwards) can be raised if closing the pipe
              used to talk to the dialog-like program fails.

        """
        p = self._gauge_process
        # Close the pipe that we are using to feed dialog's stdin
        with _OSErrorHandling():
            p["stdin"].close()
        # According to dialog(1), the output should always be empty.
        exit_code = \
                  self._wait_for_program_termination(p["pid"],
                                                     p["child_output_rfd"])[0]
        return exit_code

    @widget
    @retval_is_code
    def infobox(self, text, height=10, width=30, **kwargs):
        """Display an information dialog box.

        text   -- text to display in the box
        height -- height of the box
        width  -- width of the box

        An info box is basically a message box. However, in this
        case, dialog will exit immediately after displaying the
        message to the user. The screen is not cleared when dialog
        exits, so that the message will remain on the screen after
        the method returns. This is useful when you want to inform
        the user that some operations are carrying on that may
        require some time to finish.

        Return the Dialog exit code from the backend.

        Notable exceptions:

            any exception raised by self._perform()

        """
        return self._widget_with_no_output(
            "infobox",
            ["--infobox", text, unicode(height), unicode(width)],
            kwargs)

    @widget
    def inputbox(self, text, height=10, width=30, init='', **kwargs):
        """Display an input dialog box.

        text   -- text to display in the box
        height -- height of the box
        width  -- width of the box
        init   -- default input string

        An input box is useful when you want to ask questions that
        require the user to input a string as the answer. If init is
        supplied it is used to initialize the input string. When
        entering the string, the BACKSPACE key can be used to
        correct typing errors. If the input string is longer than
        can fit in the dialog box, the input field will be scrolled.

        Return a tuple of the form (code, string) where 'code' is the
        Dialog exit code and 'string' is the string entered by the
        user.

        Notable exceptions:

            any exception raised by self._perform()

        """
        # The help output does not depend on whether --help-status was passed
        # (dialog 1.2-20130902).
        return self._widget_with_string_output(
            ["--inputbox", text, unicode(height), unicode(width), init],
            kwargs, strip_xdialog_newline=True, raw_help=True)

    @widget
    def inputmenu(self, text, height=0, width=60, menu_height=7, choices=[],
             **kwargs):
        """Display an inputmenu dialog box.

        text        -- text to display in the box
        height      -- height of the box
        width       -- width of the box
        menu_height -- height of the menu (scrollable part)
        choices     -- a sequence of (tag, item) tuples, the meaning
                       of which is explained below


        Overview
        --------

        An inputmenu box is a dialog box that can be used to present
        a list of choices in the form of a menu for the user to
        choose. Choices are displayed in the given order. The main
        differences with the menu dialog box are:

          * entries are not automatically centered, but
            left-adjusted;

          * the current entry can be renamed by pressing the Rename
            button, which allows editing the 'item' part of the
            current entry.

        Each menu entry consists of a 'tag' string and an 'item'
        string. The tag gives the entry a name to distinguish it from
        the other entries in the menu and to provide quick keyboard
        access. The item is a short description of the option that
        the entry represents.

        The user can move between the menu entries by pressing the
        UP/DOWN keys or the first letter of the tag as a hot key.
        There are 'menu_height' lines (not entries!) displayed in the
        scrollable part of the menu at one time.

        BEWARE!

          It is strongly advised not to put any space in tags,
          otherwise the dialog output can be ambiguous if the
          corresponding entry is renamed, causing pythondialog to
          return a wrong tag string and new item text.

          The reason is that in this case, the dialog output is
          "RENAMED <tag> <item>" (without angle brackets) and
          pythondialog cannot guess whether spaces after the
          "RENAMED " prefix belong to the <tag> or the new <item>
          text.

        Note: there is no point in calling this method with
              'help_status=True', because it is not possible to
              rename several items nor is it possible to choose the
              Help button (or any button other than Rename) once one
              has started to rename an item.

        Return value
        ------------

        Return a tuple of the form (exit_info, tag, new_item_text)
        where:

        'exit_info' is either:
          - the string "accepted", meaning that an entry was accepted
            without renaming;
          - the string "renamed", meaning that an entry was accepted
            after being renamed;
          - one of the standard Dialog exit codes Dialog.CANCEL,
            Dialog.ESC, Dialog.HELP.

        'tag' indicates which entry was accepted (with or without
        renaming), if any. If no entry was accepted (e.g., if the
        dialog was exited with the Cancel button), then 'tag' is
        None.

        'new_item_text' gives the new 'item' part of the renamed
        entry if 'exit_info' is "renamed", otherwise it is None.

        Notable exceptions:

            any exception raised by self._perform()

        """
        cmd = ["--inputmenu", text, unicode(height), unicode(width), unicode(menu_height)]
        for t in choices:
            cmd.extend(t)
        (code, output) = self._perform(cmd, **kwargs)

        if code == self.HELP:
            help_id = self._parse_help(output, kwargs)
            return (code, help_id, None)
        elif code == self.OK:
            return ("accepted", output, None)
        elif code == self.EXTRA:
            if not output.startswith("RENAMED "):
                raise PythonDialogBug(
                    "'output' does not start with 'RENAMED ': {0!r}".format(
                        output))
            t = output.split(' ', 2)
            return ("renamed", t[1], t[2])
        else:
            return (code, None, None)

    @widget
    def menu(self, text, height=15, width=54, menu_height=7, choices=[],
             **kwargs):
        """Display a menu dialog box.

        text        -- text to display in the box
        height      -- height of the box
        width       -- width of the box
        menu_height -- number of entries displayed in the box (which
                       can be scrolled) at a given time
        choices     -- a sequence of (tag, item) tuples (see below)


        Overview
        --------

        As its name suggests, a menu box is a dialog box that can be
        used to present a list of choices in the form of a menu for
        the user to choose. Choices are displayed in the given order.

        Each menu entry consists of a 'tag' string and an 'item'
        string. The tag gives the entry a name to distinguish it from
        the other entries in the menu and to provide quick keyboard
        access. The item is a short description of the option that
        the entry represents.

        The user can move between the menu entries by pressing the
        UP/DOWN keys, the first letter of the tag as a hot key, or
        the number keys 1-9. There are 'menu_height' entries
        displayed in the menu at one time, but the menu will be
        scrolled if there are more entries than that.


        Return value
        ------------

        Return a tuple of the form (code, tag) where 'code' is the
        Dialog exit code and 'tag' the tag string of the item that
        the user chose.

        Notable exceptions:

            any exception raised by self._perform()

        """
        cmd = ["--menu", text, unicode(height), unicode(width), unicode(menu_height)]
        for t in choices:
            cmd.extend(t)

        return self._widget_with_string_output(
            cmd, kwargs, strip_xdialog_newline=True)

    @widget
    @retval_is_code
    def mixedgauge(self, text, height=0, width=0, percent=0, elements=[],
             **kwargs):
        """Display a mixed gauge dialog box.

        text        -- text to display in the middle of the box,
                       between the elements list and the progress bar
        height      -- height of the box
        width       -- width of the box
        percent     -- integer giving the percentage for the global
                       progress bar
        elements    -- a sequence of (tag, item) tuples, the meaning
                       of which is explained below

        A mixedgauge box displays a list of "elements" with status
        indication for each of them, followed by a text and finally a
        (global) progress bar along the bottom of the box.

        The top part ('elements') is suitable for displaying a task
        list. One element is displayed per line, with its 'tag' part
        on the left and its 'item' part on the right. The 'item' part
        is a string that is displayed on the right of the same line.

        The 'item' of an element can be an arbitrary string, but
        special values listed in the dialog(3) manual page translate
        into a status indication for the corresponding task ('tag'),
        such as: "Succeeded", "Failed", "Passed", "Completed", "Done",
        "Skipped", "In Progress", "Checked", "N/A" or a progress
        bar.

        A progress bar for an element is obtained by supplying a
        negative number for the 'item'. For instance, "-75" will
        cause a progress bar indicating 75 % to be displayed on the
        corresponding line.

        For your convenience, if an 'item' appears to be an integer
        or a float, it will be converted to a string before being
        passed to the dialog-like program.

        'text' is shown as a sort of caption between the list and the
        global progress bar. The latter displays 'percent' as the
        percentage of completion.

        Contrary to the gauge widget, mixedgauge is completely
        static. You have to call mixedgauge() several times in order
        to display different percentages in the global progress bar,
        or status indicators for a given task.

        Return the Dialog exit code from the backend.

        Notable exceptions:

            any exception raised by self._perform()

        """
        cmd = ["--mixedgauge", text, unicode(height), unicode(width), unicode(percent)]
        for t in elements:
            cmd.extend( (t[0], unicode(t[1])) )
        return self._widget_with_no_output("mixedgauge", cmd, kwargs)

    @widget
    @retval_is_code
    def msgbox(self, text, height=10, width=30, **kwargs):
        """Display a message dialog box, with scrolling and line wrapping.

        text   -- text to display in the box
        height -- height of the box
        width  -- width of the box

        Display a text in a message box, with a scrollbar and
        percentage indication if the text is too long to fit in a
        single "screen".

        A message box is very similar to a yes/no box. The only
        difference between a message box and a yes/no box is that a
        message box has only a single OK button. You can use this
        dialog box to display any message you like. After reading
        the message, the user can press the Enter key so that dialog
        will exit and the calling program can continue its
        operation.

        msgbox() performs automatic line wrapping. If you want to
        force a newline at some point, simply insert it in 'text'. In
        other words (with the default settings), newline characters
        in 'text' *are* respected; the line wrapping process
        performed by dialog only inserts *additional* newlines when
        needed. If you want no automatic line wrapping, consider
        using scrollbox().

        Return the Dialog exit code from the backend.

        Notable exceptions:

            any exception raised by self._perform()

        """
        return self._widget_with_no_output(
            "msgbox",
            ["--msgbox", text, unicode(height), unicode(width)],
            kwargs)

    @widget
    @retval_is_code
    def pause(self, text, height=15, width=60, seconds=5, **kwargs):
        """Display a pause dialog box.

        text       -- text to display in the box
        height     -- height of the box
        width      -- width of the box
        seconds    -- number of seconds to pause for (integer)

        A pause box displays a text and a meter along the bottom of
        the box, during a specified amount of time ('seconds'). The
        meter indicates how many seconds remain until the end of the
        pause. The widget exits when the specified number of seconds
        is elapsed, or immediately if the user presses the OK button,
        the Cancel button or the Esc key.

        Return the Dialog exit code, which is Dialog.OK if the pause
        ended automatically after 'seconds' seconds or if the user
        pressed the OK button.

        Notable exceptions:

            any exception raised by self._perform()

        """
        return self._widget_with_no_output(
            "pause",
            ["--pause", text, unicode(height), unicode(width), unicode(seconds)],
            kwargs)

    @widget
    def passwordbox(self, text, height=10, width=60, init='', **kwargs):
        """Display a password input dialog box.

        text   -- text to display in the box
        height -- height of the box
        width  -- width of the box
        init   -- default input password

        A password box is similar to an input box, except that the
        text the user enters is not displayed. This is useful when
        prompting for passwords or other sensitive information. Be
        aware that if anything is passed in "init", it will be
        visible in the system's process table to casual snoopers.
        Also, it is very confusing to the user to provide them with a
        default password they cannot see. For these reasons, using
        "init" is highly discouraged.

        By default (as in dialog), nothing is echoed to the terminal
        as the user enters the sensitive text. This can be confusing
        to users. Use the 'insecure' keyword argument if you want an
        asterisk to be echoed for each character entered by the user.

        Return a tuple of the form (code, password) where 'code' is
        the Dialog exit code and 'password' is the password entered
        by the user.

        Notable exceptions:

            any exception raised by self._perform()

        """
        # The help output does not depend on whether --help-status was passed
        # (dialog 1.2-20130902).
        return self._widget_with_string_output(
            ["--passwordbox", text, unicode(height), unicode(width), init],
            kwargs, strip_xdialog_newline=True, raw_help=True)

    def _progressboxoid(self, widget, file_path=None, file_flags=os.O_RDONLY,
                        fd=None, text=None, height=20, width=78, **kwargs):
        if (file_path is None and fd is None) or \
                (file_path is not None and fd is not None):
            raise BadPythonDialogUsage(
                "{0}.{1}.{2}: either 'file_path' or 'fd' must be provided, and "
                "not both at the same time".format(
                    __name__, self.__class__.__name__, widget))

        with _OSErrorHandling():
            if file_path is not None:
                if fd is not None:
                    raise PythonDialogBug(
                        "unexpected non-None value for 'fd': {0!r}".format(fd))
                # No need to pass 'mode', as the file is not going to be
                # created here.
                fd = os.open(file_path, file_flags)

            try:
                args = [ "--{0}".format(widget) ]
                if text is not None:
                    args.append(text)
                args.extend([unicode(height), unicode(width)])

                kwargs["redir_child_stdin_from_fd"] = fd
                code = self._widget_with_no_output(widget, args, kwargs)
            finally:
                with _OSErrorHandling():
                    if file_path is not None:
                        # We open()ed file_path ourselves, let's close it now.
                        os.close(fd)

        return code

    @widget
    @retval_is_code
    def progressbox(self, file_path=None, file_flags=os.O_RDONLY,
                    fd=None, text=None, height=20, width=78, **kwargs):
        """Display a possibly growing stream in a dialog box, as with "tail -f".

          file_path  -- path to the file that is going to be displayed
          file_flags -- flags used when opening 'file_path'; those
                        are passed to os.open() function (not the
                        built-in open function!). By default, only
                        one flag is used: os.O_RDONLY.

        OR, ALTERNATIVELY:

          fd       -- file descriptor for the stream to be displayed

        text     -- caption continuously displayed at the top, above the
                    stream text, or None to disable the caption
        height   -- height of the box
        width    -- width of the box

        Display the contents of the specified file, updating the
        dialog box whenever the file grows, as with the "tail -f"
        command.

        The file can be specified in two ways:
          - either by giving its path (and optionally os.open()
            flags) with parameters 'file_path' and 'file_flags';
          - or by passing its file descriptor with parameter 'fd' (in
            which case it may not even be a file; for instance, it
            could be an anonymous pipe created with os.pipe()).

        Return the Dialog exit code from the backend.

        Notable exceptions:

            PythonDialogIOError    if the Python version is < 3.3
            PythonDialogOSError
            any exception raised by self._perform()

        """
        return self._progressboxoid(
            "progressbox", file_path=file_path, file_flags=file_flags,
            fd=fd, text=text, height=height, width=width, **kwargs)

    @widget
    @retval_is_code
    def programbox(self, file_path=None, file_flags=os.O_RDONLY,
                   fd=None, text=None, height=20, width=78, **kwargs):
        """Display a possibly growing stream in a dialog box, as with "tail -f".

        A programbox is very similar to a progressbox. The only
        difference between a program box and a progress box is that a
        program box displays an OK button, but only after the input
        stream has been exhausted (i.e., End Of File has been
        reached).

        This dialog box can be used to display the piped output of an
        external program. After the program completes, the user can
        press the Enter key to close the dialog and resume execution
        of the calling program.

        The parameters and exceptions are the same as for
        'progressbox'. Please refer to the corresponding
        documentation.

        This widget requires dialog >= 1.1 (2011-03-02).

        """
        self._dialog_version_check("1.1", "the programbox widget")
        return self._progressboxoid(
            "programbox", file_path=file_path, file_flags=file_flags,
            fd=fd, text=text, height=height, width=width, **kwargs)

    @widget
    def radiolist(self, text, height=15, width=54, list_height=7,
                  choices=[], **kwargs):
        """Display a radiolist box.

        text        -- text to display in the box
        height      -- height of the box
        width       -- width of the box
        list_height -- number of entries displayed in the box (which
                       can be scrolled) at a given time
        choices     -- a list of tuples (tag, item, status) where
                       'status' specifies the initial on/off state of
                       each entry; can be True or False, 1 or 0, "on"
                       or "off" (True and 1 meaning "on"), or any case
                       variation of these two strings. No more than
                       one entry should be set to True.

        A radiolist box is similar to a menu box. The main difference
        is that you can indicate which entry is initially selected,
        by setting its status to True.

        Return a tuple of the form (code, tag) with the tag for the
        entry that was chosen by the user. 'code' is the Dialog exit
        code from the backend.

        If the user exits with ESC or CANCEL, or if all entries were
        initially set to False and not altered before the user chose
        OK, the returned tag is the empty string.

        Notable exceptions:

            any exception raised by self._perform() or _to_onoff()

        """
        cmd = ["--radiolist", text, unicode(height), unicode(width), unicode(list_height)]
        for t in choices:
            cmd.extend([ t[0], t[1], _to_onoff(t[2]) ] + list(t[3:]))
        (code, output) = self._perform(cmd, **kwargs)

        output = self._strip_xdialog_newline(output)

        if code == self.HELP:
            help_data = self._parse_help(output, kwargs)
            if self._help_status_on(kwargs):
                help_id, selected_tag = help_data

                # Reconstruct 'choices' with the selected item inferred from
                # 'selected_tag'.
                updated_choices = []
                for elt in choices:
                    tag, item, status = elt[:3]
                    rest = elt[3:]
                    updated_choices.append([ tag, item, tag == selected_tag ]
                                           + list(rest))

                return (code, (help_id, selected_tag, updated_choices))
            else:
                return (code, help_data)
        else:
            return (code, output)

    @widget
    def rangebox(self, text, height=0, width=0, min=None, max=None, init=None,
                 **kwargs):
        """Display an range dialog box.

        text   -- text to display above the actual range control
        height -- height of the box
        width  -- width of the box
        min    -- minimum value for the range control
        max    -- maximum value for the range control
        init   -- initial value for the range control

        The rangebox dialog allows the user to select from a range of
        values using a kind of slider. The range control shows the
        current value as a bar (like the gauge dialog).

        The return value is a tuple of the form (code, val) where
        'code' is the Dialog exit code and 'val' is an integer: the
        value chosen by the user.

        The Tab and arrow keys move the cursor between the buttons
        and the range control. When the cursor is on the latter, you
        can change the value with the following keys:

          Left/Right arrows   select a digit to modify

          +/-                 increment/decrement the selected digit
                              by one unit

          0-9                 set the selected digit to the given
                              value

        Some keys are also recognized in all cursor positions:

          Home/End            set the value to its minimum or maximum

          PageUp/PageDown     decrement/increment the value so that
                              the slider moves by one column

        This widget requires dialog >= 1.2 (2012-12-30).

        Notable exceptions:

            any exception raised by self._perform()

        """
        self._dialog_version_check("1.2", "the rangebox widget")

        for name in ("min", "max", "init"):
            if not isinstance(locals()[name], int):
                raise BadPythonDialogUsage(
                    "'{0}' argument not an int: {1!r}".format(name,
                                                              locals()[name]))
        (code, output) = self._perform(
            ["--rangebox", text] + [ unicode(i) for i in
                                     (height, width, min, max, init) ],
            **kwargs)

        if code == self.HELP:
            help_data = self._parse_help(output, kwargs, raw_format=True)
            # The help output does not depend on whether --help-status was
            # passed (dialog 1.2-20130902).
            return (code, int(help_data))
        elif code in (self.OK, self.EXTRA):
            return (code, int(output))
        else:
            return (code, None)

    @widget
    @retval_is_code
    def scrollbox(self, text, height=20, width=78, **kwargs):
        """Display a string in a scrollable box, with no line wrapping.

        text   -- string to display in the box
        height -- height of the box
        width  -- width of the box

        This method is a layer on top of textbox. The textbox widget
        in dialog allows to display file contents only. This method
        allows you to display any text in a scrollable box. This is
        simply done by creating a temporary file, calling textbox() and
        deleting the temporary file afterwards.

        The text is not automatically wrapped. New lines in the
        scrollable box will be placed exactly as in 'text'. If you
        want automatic line wrapping, you should use the msgbox
        widget instead (the 'textwrap' module from the Python
        standard library is also worth knowing about).

        Return the Dialog exit code from the backend.

        Notable exceptions:
            - UnableToCreateTemporaryDirectory
            - PythonDialogIOError    if the Python version is < 3.3
            - PythonDialogOSError
            - exceptions raised by the tempfile module (which are
              unfortunately not mentioned in its documentation, at
              least in Python 2.3.3...)

        """
        # In Python < 2.3, the standard library does not have
        # tempfile.mkstemp(), and unfortunately, tempfile.mktemp() is
        # insecure. So, I create a non-world-writable temporary directory and
        # store the temporary file in this directory.
        with _OSErrorHandling():
            tmp_dir = _create_temporary_directory()
            fName = os.path.join(tmp_dir, "text")
            # If we are here, tmp_dir *is* created (no exception was raised),
            # so chances are great that os.rmdir(tmp_dir) will succeed (as
            # long as tmp_dir is empty).
            #
            # Don't move the _create_temporary_directory() call inside the
            # following try statement, otherwise the user will always see a
            # PythonDialogOSError instead of an
            # UnableToCreateTemporaryDirectory because whenever
            # UnableToCreateTemporaryDirectory is raised, the subsequent
            # os.rmdir(tmp_dir) is bound to fail.
            try:
                # No race condition as with the deprecated tempfile.mktemp()
                # since tmp_dir is not world-writable.
                with open(fName, mode="w") as f:
                    f.write(text)

                # Ask for an empty title unless otherwise specified
                if kwargs.get("title", None) is None:
                    kwargs["title"] = ""

                return self._widget_with_no_output(
                    "textbox",
                    ["--textbox", fName, unicode(height), unicode(width)],
                    kwargs)
            finally:
                if os.path.exists(fName):
                    os.unlink(fName)
                os.rmdir(tmp_dir)

    @widget
    @retval_is_code
    def tailbox(self, filename, height=20, width=60, **kwargs):
        """Display the contents of a file in a dialog box, as with "tail -f".

        filename -- name of the file, the contents of which is to be
                    displayed in the box
        height   -- height of the box
        width    -- width of the box

        Display the contents of the specified file, updating the
        dialog box whenever the file grows, as with the "tail -f"
        command.

        Return the Dialog exit code from the backend.

        Notable exceptions:

            any exception raised by self._perform()

        """
        return self._widget_with_no_output(
            "tailbox",
            ["--tailbox", filename, unicode(height), unicode(width)],
            kwargs)
    # No tailboxbg widget, at least for now.

    @widget
    @retval_is_code
    def textbox(self, filename, height=20, width=60, **kwargs):
        """Display the contents of a file in a dialog box.

        filename -- name of the file whose contents is to be
                    displayed in the box
        height   -- height of the box
        width    -- width of the box

        A text box lets you display the contents of a text file in a
        dialog box. It is like a simple text file viewer. The user
        can move through the file by using the UP/DOWN, PGUP/PGDN
        and HOME/END keys available on most keyboards. If the lines
        are too long to be displayed in the box, the LEFT/RIGHT keys
        can be used to scroll the text region horizontally. For more
        convenience, forward and backward searching functions are
        also provided.

        Return the Dialog exit code from the backend.

        Notable exceptions:

            any exception raised by self._perform()

        """
        # This is for backward compatibility... not that it is
        # stupid, but I prefer explicit programming.
        if kwargs.get("title", None) is None:
            kwargs["title"] = filename
        return self._widget_with_no_output(
            "textbox",
            ["--textbox", filename, unicode(height), unicode(width)],
            kwargs)

    def _timebox_parse_time(self, time_str):
        try:
            mo = _timebox_time_cre.match(time_str)
        except re.error, e:
            raise PythonDialogReModuleError(unicode(e))

        if not mo:
            raise UnexpectedDialogOutput(
                "the dialog-like program returned the following "
                "unexpected output (a time string was expected) with the "
                "--timebox option: {0!r}".format(time_str))

        return [ int(s) for s in mo.group("hour", "minute", "second") ]

    @widget
    def timebox(self, text, height=3, width=30, hour=-1, minute=-1,
                second=-1, **kwargs):
        """Display a time dialog box.

        text   -- text to display in the box
        height -- height of the box
        width  -- width of the box
        hour   -- inititial hour selected
        minute -- inititial minute selected
        second -- inititial second selected

        A dialog is displayed which allows you to select hour, minute
        and second. If the values for hour, minute or second are
        negative (or not explicitely provided, as they default to
        -1), the current time's corresponding values are used. You
        can increment or decrement any of those using the left-, up-,
        right- and down-arrows. Use tab or backtab to move between
        windows.

        Return a tuple of the form (code, time) where:
          - 'code' is the Dialog exit code;
          - 'time' is a list of the form [hour, minute, second],
            where 'hour', 'minute' and 'second' are integers
            corresponding to the time chosen by the user.

        Notable exceptions:
            - any exception raised by self._perform()
            - PythonDialogReModuleError
            - UnexpectedDialogOutput

        """
        (code, output) = self._perform(
            ["--timebox", text, unicode(height), unicode(width),
               unicode(hour), unicode(minute), unicode(second)],
            **kwargs)

        if code == self.HELP:
            help_data = self._parse_help(output, kwargs, raw_format=True)
            # The help output does not depend on whether --help-status was
            # passed (dialog 1.2-20130902).
            return (code, self._timebox_parse_time(help_data))
        elif code in (self.OK, self.EXTRA):
            return (code, self._timebox_parse_time(output))
        else:
            return (code, None)

    @widget
    def treeview(self, text, height=0, width=0, list_height=0,
                 nodes=[], **kwargs):
        """Display a treeview box.

        text        -- text to display at the top of the box
        height      -- height of the box
        width       -- width of the box
        list_height -- number of lines reserved for the main part of
                       the box, where the tree is displayed
        nodes       -- a list of (tag, item, status, depth) tuples
                       describing nodes, where:
                         - 'tag' is used to indicate which node was
                           selected by the user on exit;
                         - 'item' is the text displayed for the node;
                         - 'status' specifies the initial on/off
                           state of each node; can be True or False,
                           1 or 0, "on" or "off" (True, 1 and "on"
                           meaning selected), or any case variation
                           of these two strings;
                         - 'depth' is a non-negative integer
                           indicating the depth of the node in the
                           tree (0 for the root node).

        Display nodes organized in a tree structure. Each node has a
        tag, an 'item' text, a selected status, and a depth in the
        tree. Only the 'item' texts are displayed in the widget; tags
        are only used for the return value. Only one node can be
        selected at a given time, as for the radiolist widget.

        Return a tuple of the form (code, tag) where:
          - 'code' is the Dialog exit code from the backend;
          - 'tag' is the tag of the selected node.

        This widget requires dialog >= 1.2 (2012-12-30).

        Notable exceptions:

            any exception raised by self._perform() or _to_onoff()

        """
        self._dialog_version_check("1.2", "the treeview widget")
        cmd = ["--treeview", text, unicode(height), unicode(width), unicode(list_height)]

        nselected = 0
        for i, t in enumerate(nodes):
            if not isinstance(t[3], int):
                raise BadPythonDialogUsage(
                    "fourth element of node {0} not an int: {1!r}".format(
                        i, t[3]))

            status = _to_onoff(t[2])
            if status == "on":
                nselected += 1

            cmd.extend([ t[0], t[1], status, unicode(t[3]) ] + list(t[4:]))

        if nselected != 1:
            raise BadPythonDialogUsage(
                "exactly one node must be selected, not {0}".format(nselected))

        (code, output) = self._perform(cmd, **kwargs)

        if code == self.HELP:
            help_data = self._parse_help(output, kwargs)
            if self._help_status_on(kwargs):
                help_id, selected_tag = help_data

                # Reconstruct 'nodes' with the selected item inferred from
                # 'selected_tag'.
                updated_nodes = []
                for elt in nodes:
                    tag, item, status = elt[:3]
                    rest = elt[3:]
                    updated_nodes.append([ tag, item, tag == selected_tag ]
                                         + list(rest))

                return (code, (help_id, selected_tag, updated_nodes))
            else:
                return (code, help_data)
        elif code in (self.OK, self.EXTRA):
            return (code, output)
        else:
            return (code, None)

    @widget
    @retval_is_code
    def yesno(self, text, height=10, width=30, **kwargs):
        """Display a yes/no dialog box.

        text   -- text to display in the box
        height -- height of the box
        width  -- width of the box

        A yes/no dialog box of size 'height' rows by 'width' columns
        will be displayed. The string specified by 'text' is
        displayed inside the dialog box. If this string is too long
        to fit in one line, it will be automatically divided into
        multiple lines at appropriate places. The text string can
        also contain the sub-string "\\n" or newline characters to
        control line breaking explicitly. This dialog box is useful
        for asking questions that require the user to answer either
        yes or no. The dialog box has a Yes button and a No button,
        in which the user can switch between by pressing the TAB
        key.

        Return the Dialog exit code from the backend.

        Notable exceptions:

            any exception raised by self._perform()

        """
        return self._widget_with_no_output(
            "yesno",
            ["--yesno", text, unicode(height), unicode(width)],
            kwargs)
