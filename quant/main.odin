package main

QUANT_DIR :: ".quant"

main :: proc() {
    // filepath, err := os.read_link("test", context.temp_allocator)
    // fmt.printfln("filepath = %v, err = %v", filepath, err)
    os.exit(main_run())
}


File :: struct {
    file_info: os.File_Info,
    ignored: bool,
}


main_run :: proc() -> int {
    Cli_Options :: struct {
        command: string `args:"pos=0"`
    }

    cli_options: Cli_Options
    flags.parse_or_exit(&cli_options, os.args)

    command := cli_options.command

    context.logger = log.create_console_logger()
    defer log.destroy_console_logger(context.logger)

    if command == "" {
        flags.write_usage(os.to_writer(os.stderr), Cli_Options, os.args[0])
        return -1
    } else if command == "init" {
        init_err := init_repository()
        #partial switch init_err {
        case .None:
            log.info("Repository initialized successfully.")
        case .Exist:
            log.info("Repository already exist.")
        case:
            log.errorf("Initialization error: %v", init_err)
            return -1
        }
    } else if command == "status" {
        files, err := walk_directory_recursive(".")
        ensure(err == nil)
        for f in files {
            fmt.printfln("%v (%v)", f.file_info.fullpath, f.file_info.type)
        }
    } else {
        log.errorf("Unknown command: %v", cli_options.command)
        return -1
    }

    return 0
}


Init_Error :: enum {
    None,
    Os_Error,
    File_Collision,
    Exist,
}

@(require_results)
init_repository :: proc() -> Init_Error {
    if os.exists(QUANT_DIR) {
        if !os.is_directory(QUANT_DIR) {
            log.errorf("File with a name `%s/` already exists in root directory. Please move or delete it.", QUANT_DIR)
            return .File_Collision
        }
        return .Exist
    }
    os_err := os.make_directory(QUANT_DIR)
    if os_err != nil {
        log.errorf("OS error: %v", os_err)
        return .Os_Error
    }
    return .None
}


@(require_results)
walk_directory_recursive :: proc(root_path: string, max_depth := -1, allocator := context.allocator) -> (files: []File, err: os.Error) {
    assert(allocator.procedure != nil)

    clone_file_info :: proc(fi: os.File_Info, allocator: runtime.Allocator) -> os.File_Info {
        cloned := fi
        cloned.fullpath = strings.clone(fi.fullpath, allocator)
        cloned.name = strings.clone(fi.name, allocator)
        return cloned
    }

    helper :: proc(files: ^[dynamic]File, dir_path: string, depth, max_depth: int, allocator: runtime.Allocator) -> os.Error {
        if max_depth >= 0 && depth >= max_depth {
            return nil
        }

        dir := os.open(dir_path) or_return
        defer os.close(dir)

        it := os.read_directory_iterator_create(dir)
        defer os.read_directory_iterator_destroy(&it)

        for file_info, index in os.read_directory_iterator(&it) {
            #partial switch file_info.type {
            case .Directory:
                helper(files, file_info.fullpath, depth+1, max_depth, allocator) or_return

            case .Regular:
                append(files, File{ file_info = clone_file_info(file_info, allocator) }) or_return

            case .Symlink:
                // TODO: Maybe it's not a good idea to save symlinks. Git saves symlinks as paths to target and then recreates them. I don't now for now how to manage this.
                log.error("TODO: Make saving symlinks.")

            case:
                log.errorf("Unsupported file type: %v. Skipping. For now it is possible to save only regular files.", file_info.type)
            }
        }
        return nil
    }

    files_d := make([dynamic]File, allocator) or_return
    defer if err != nil {
        delete(files_d)
    }
    helper(&files_d, root_path, 0, max_depth, allocator) or_return

    return files_d[:], nil
}

import "core:fmt"
import "core:os"
import "core:flags"
import "core:log"
import "core:strings"

import "base:runtime"
