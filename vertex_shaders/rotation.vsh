attribute vec4 aPosition;
attribute vec2 aTextCoord;

uniform mat4 uProjection;
uniform mat4 uModelView;
uniform float angle;  ///angle 旋转角度  M_PI_2等

varying vec2 vTextCoord;

void main(void) {
    mat2 rotation = mat2(
        cos(angle), -sin(angle),
        sin(angle), cos(angle)
    );
    vTextCoord = ((aTextCoord - vec2(0.5, 0.5)) * rotation) + vec2(0.5, 0.5);
    gl_Position = uProjection * uModelView * aPosition;
}
