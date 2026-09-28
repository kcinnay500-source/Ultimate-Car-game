use mlua::{Lua, Result, Value, Function};
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 { eprintln!("usage: luaurun check <files...> | run <file> [args]"); std::process::exit(2); }
    let lua = Lua::new();
    let code = match args[1].as_str() {
        "check" => {
            let mut bad = 0;
            for f in &args[2..] {
                let src = fs::read_to_string(f).expect("read");
                match lua.load(&src).set_name(format!("@{}", f)).into_function() {
                    Ok(_) => {}
                    Err(e) => { eprintln!("FEHLER {}: {}", f, e); bad += 1; }
                }
            }
            println!("Luau-Compiler: {} Dateien, {} Fehler", args.len() - 2, bad);
            if bad > 0 { 1 } else { 0 }
        }
        "run" => match run(&lua, &args[2], &args[3..]) {
            Ok(()) => 0,
            Err(e) => { eprintln!("LAUFZEITFEHLER: {}", e); 1 }
        },
        _ => 2,
    };
    std::process::exit(code);
}

fn run(lua: &Lua, file: &str, rest: &[String]) -> Result<()> {
    let g = lua.globals();
    g.set("readfile", lua.create_function(|_, p: String| {
        fs::read_to_string(&p).map_err(|e| mlua::Error::runtime(format!("{}: {}", p, e)))
    })?)?;
    g.set("listdir", lua.create_function(|lua, p: String| {
        let mut names: Vec<String> = fs::read_dir(&p)
            .map_err(|e| mlua::Error::runtime(format!("{}: {}", p, e)))?
            .filter_map(|e| e.ok())
            .filter(|e| e.path().is_file())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        let t = lua.create_table()?;
        for (i, n) in names.iter().enumerate() { t.set(i + 1, n.as_str())?; }
        Ok(t)
    })?)?;
    g.set("loadsource", lua.create_function(|lua, (src, name): (String, String)| {
        let f: Function = lua.load(&src).set_name(format!("@{}", name)).into_function()?;
        Ok(f)
    })?)?;
    let t = lua.create_table()?;
    for (i, a) in rest.iter().enumerate() { t.set(i + 1, a.as_str())?; }
    g.set("ARGS", t)?;
    let src = fs::read_to_string(file).map_err(|e| mlua::Error::runtime(e.to_string()))?;
    let _: Value = lua.load(&src).set_name(format!("@{}", file)).eval()?;
    Ok(())
}
