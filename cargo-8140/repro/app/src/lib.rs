#[inline(never)]
fn app(x: u32) -> u32 { x.wrapping_mul(pm::seven!()) }

#[no_mangle]
pub extern "C" fn run(x: u32) -> u32 { app(leaf::leaf(x)) + bs::bs(x) }
