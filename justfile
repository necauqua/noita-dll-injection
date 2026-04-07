
@_:
    just -ul

build:
    for dir in examples/*; do cd "$dir" && zig build -freference-trace=16 && cd - > /dev/null; done

install noita-dir: build
    for dir in examples/*; do cp "$dir"/zig-out/*.asi "{{noita-dir}}/plugins/"; done

clean:
    find . \( -name .zig-cache -o -name zig-out \) -exec rm -rf -- {} +
