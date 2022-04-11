set confirm off
set print pretty on
set prompt \033[31mgdb $ \033[0m

# Load gdbinit files wherever they are when we drop into gdb.
set auto-load safe-path /

#--------------------------------------------------------------------
# Functions

define var
    if $argc == 0
        info variables
    end
    if $argc == 1
        info variables $arg0
    end
    if $argc > 1
        help var
    end
end
document var
Print all global and static variable names (symbols), or those matching REGEXP.
Usage: var <REGEXP>
end
