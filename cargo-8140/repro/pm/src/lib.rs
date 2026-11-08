use proc_macro::TokenStream;
#[proc_macro]
pub fn seven(_: TokenStream) -> TokenStream { "7".parse().unwrap() }
