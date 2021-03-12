function render(x) {
    var ctx = document.getElementById('canvas').getContext('2d')
    ctx.fillStyle = "#000000";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#ffffff";

    for (i = 0; i < 32; ++i) {
        for (j = 63; j >= 0; --j) {
            if ((x >> j & 1) != 0)
                ctx.fillRect(16 * (64 - 1 - j), 16 * i, 16,16)
        }
    }
}

chip8load()

function step(timestamp) {
    chip8cycle()
    render(chip8getvram())
    console.log(chip8getvram())
    window.requestAnimationFrame(step)
}
window.requestAnimationFrame(step)