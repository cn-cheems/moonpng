///|
fn main {
  ignore(@env.args())
  println("moonpng-guard reads files through the JavaScript target")
  println("Usage: moon run cmd/guard --target js -- <file.png> [more.png ...]")
}
