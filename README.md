# MiniChat

MiniChat es una aplicación de chat minimalista que permite interactuar con modelos de lenguaje de IA a través de APIs compatibles con OpenAI.

## Características

- Interfaz de chat limpia y minimalista
- Soporte para múltiples proveedores de IA (OpenAI, Azure OpenAI, Ollama, etc.)
- Visualización de mensajes con formato Markdown
- Historial de conversaciones
- Generación automática de títulos para conversaciones
- Selección de modelos desde el endpoint
- Soporte para imágenes (adjuntar y analizar imágenes)
- Configuración personalizable

## Instalación

Simplemente abre el archivo `index.html` en tu navegador web. No requiere instalación adicional.

## Configuración

1. Haz clic en el ícono de engrane (⚙️) para abrir el panel de configuración
2. Ingresa la URL base del endpoint (ej. `https://api.openai.com/v1` o `http://localhost:11434/v1`)
3. Ingresa tu clave de API
4. Haz clic en el campo de modelo para cargar la lista de modelos disponibles
5. Selecciona un modelo de la lista
6. Opcionalmente, configura un prompt del sistema
7. Guarda la configuración

## Uso

- Escribe tu mensaje en el campo de texto inferior y presiona Enter o haz clic en "Send"
- Para adjuntar una imagen, haz clic en el clip (📎) y selecciona una imagen
- Para generar un título para la conversación, haz clic en "Generate title"
- Para iniciar una nueva conversación, haz clic en "New chat"

## Funcionalidades avanzadas

### Selección de modelos
Al hacer clic en el campo de modelo en la configuración, se cargará automáticamente la lista de modelos disponibles desde el endpoint configurado. Puedes seleccionar uno de la lista desplegable.

### Historial de conversaciones
El historial de conversaciones se guarda en el almacenamiento local del navegador. Puedes acceder a conversaciones anteriores usando el menú desplegable en la parte superior derecha.

### Visualización de Markdown
Los mensajes de respuesta se muestran con formato Markdown, incluyendo soporte para código, listas, encabezados y otros elementos.

## Compatibilidad

MiniChat es compatible con cualquier servicio que tenga una API compatible con OpenAI, incluyendo:
- OpenAI GPT
- Azure OpenAI
- Ollama
- Otros servicios compatibles con OpenAI API

## Contribuciones

Las contribuciones son bienvenidas. Por favor, abre un issue o pull request en el repositorio.

## Licencia

Este proyecto es de código abierto y gratuito para uso personal y comercial.