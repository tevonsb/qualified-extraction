/*!
Project-local UniFFI bindgen binary.

This exists so you can run UniFFI bindgen on stable Cargo without relying on a
globally-installed `uniffi-bindgen` executable.

It is referenced by `Cargo.toml` as:

[[bin]]
name = "uniffi-bindgen"
path = "src/bin/uniffi-bindgen.rs"
*/

fn main() {
    uniffi::uniffi_bindgen_main()
}
