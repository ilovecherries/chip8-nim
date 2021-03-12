function render(x) {
    var ctx = document.getElementById('canvas').getContext('2d')
    ctx.fillStyle = "#000000";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#ffffff";

    for (i = 0; i < 32; ++i) {
        for (j = 63; j >= 0; --j) {
            if ((x[i][j] & 1) != 0)
                ctx.fillRect(16 * (64 - 1 - j), 16 * i, 16,16)
        }
    }
}

chip8load()
var timestep = 1000/60, lastFrameTimeMs = 0;
var then = Date.now()

function mainloop(timestamp) {
	chip8frame()
	render(chip8getvram())
	requestAnimationFrame(mainloop)
}

document.addEventListener('keydown', e => chip8keydown(e.keyCode))
document.addEventListener('keyup', e => chip8keyup(e.keyCode))

setInterval(() => chip8cycle(), 1)

requestAnimationFrame(mainloop)
