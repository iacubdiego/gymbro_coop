# Eje · rutinas y progreso en grupo

App web para registrar rutinas de gimnasio y ver el progreso propio y el de un grupo. Funciona en el celular, no necesita instalación y se aloja gratis en GitHub Pages. Los datos del grupo se guardan en [Supabase](https://supabase.com).

Cada persona configura su objetivo (salud, músculo, fuerza, resistencia o recuperación) y, si quiere, una molestia o lesión que está cuidando. Con eso la app registra el dolor de esa zona y muestra avisos de cuándo parar.

Para entrar no hace falta email ni cuenta: alcanza con el **código del grupo**, un **apodo** y un **PIN** de 4 a 8 números.

## Puesta en marcha

### 1. Supabase

1. Creá un proyecto en [supabase.com](https://supabase.com). El plan gratuito alcanza.
2. Abrí **SQL Editor**, pegá el contenido de [`supabase/schema.sql`](supabase/schema.sql) y ejecutalo. Se puede volver a ejecutar sin perder datos.
3. En **Project Settings → API Keys**, copiá la **URL del proyecto** y la **clave pública** (`sb_publishable_…`, o la `anon` en proyectos viejos).

### 2. Configuración

Completá [`config.js`](config.js):

```js
window.EJE_CONFIG = {
  supabaseUrl: 'https://TU-PROYECTO.supabase.co',
  supabaseKey: 'sb_publishable_...'
};
```

La clave pública puede estar en un repo público: las tablas tienen RLS activado y ninguna política, así que no se pueden leer ni escribir directamente. Todo pasa por funciones `eje_*` que validan el token de sesión. **Nunca pongas la clave `secret` ni la `service_role`.**

Si dejás `config.js` vacío, la app funciona igual, pero solo en el dispositivo y sin grupos.

### 3. GitHub Pages

En el repo, entrá a **Settings → Pages**, elegí *Deploy from a branch*, seleccioná la rama `main` y la carpeta `/ (root)`. En un par de minutos queda en `https://TU-USUARIO.github.io/NOMBRE-DEL-REPO/`.

## Cómo se usa

- **Crear grupo:** se elige un nombre de grupo, un apodo y un PIN. La app genera un código de 6 caracteres.
- **Invitar:** en la pestaña *Grupo*, *Compartir invitación* manda un link con el código ya cargado (`?g=CODIGO`).
- **Otro dispositivo:** se entra con el mismo código, apodo y PIN, y aparecen los mismos datos.
- **Sin grupo:** *Usar sin grupo* guarda todo solo en ese navegador. Si después se entra a un grupo, lo registrado se suma al perfil.

## Qué se comparte

El grupo ve qué días entrenó cada persona, la rutina, la duración, la cantidad de series y la mejor serie de cada ejercicio. Las notas y las indicaciones médicas nunca se comparten. El dolor se comparte solo si la persona lo activa. Cualquiera puede dejar de compartir o borrar su perfil desde la app.

## Seguridad y límites

- El PIN se guarda con hash bcrypt. Después de 5 intentos fallidos, ese apodo queda bloqueado 15 minutos.
- Quien tenga el código del grupo puede crear un perfil nuevo dentro del grupo. Compartí el código solo con quienes quieras sumar. El máximo es de 50 personas por grupo.
- Las sesiones abiertas vencen después de 180 días sin uso.
- La creación de grupos no tiene límite de frecuencia. Si la app se vuelve muy pública, conviene sumar algún control (captcha o rate limit).
- En el plan gratuito, Supabase puede pausar proyectos sin actividad. Revisá las condiciones vigentes en su sitio.

## Estructura

```
index.html           la app completa (HTML, CSS y JS en un archivo)
config.js            URL y clave pública de Supabase
supabase/schema.sql  tablas y funciones
```

## Aviso

Eje es una herramienta de registro y una guía general. No diagnostica ni reemplaza la indicación de un profesional de la salud.
