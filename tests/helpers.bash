# Writes a unified diff that adds the given files, each with N lines that mention
# money. Usage: make_diff OUT path:lines [path:lines...]
make_diff() {
    local out="$1" spec path n i
    shift
    : > "$out"
    for spec in "$@"; do
        path="${spec%%:*}"
        n="${spec##*:}"
        {
            echo "diff --git a/$path b/$path"
            echo "new file mode 100644"
            echo "--- /dev/null"
            echo "+++ b/$path"
            echo "@@ -0,0 +1,$n @@"
            i=1
            while [ "$i" -le "$n" ]; do
                echo "+\$balance = \$wallet->save(); // amount line $i"
                i=$((i + 1))
            done
        } >> "$out"
    done
}
