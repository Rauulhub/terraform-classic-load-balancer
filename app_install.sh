 #!/bin/bash
 # install httpd
 #actualizar paquetes e instalar, iniciar y para que se inicie automaticamente apache
 sudo yum update -y
 sudo yum install -y httpd
 sudo systemctl start httpd
 sudo systemctl enable httpd
 # Entrar al directorio HTML donde se encuentran los archivos del sitio web
cd /var/www/html

 # Crear un archivo index.html con contenido para la página
echo "<html>
<head>
    <title>Página de ejemplo</title>
</head>
<body>
    <h1>¡Hola desde la instancia EC2!</h1>
    <p>Esta página está alojada en una instancia EC2 detrás de un Classic Load Balancer.</p>
</body>
</html>" | sudo tee index.html > /dev/null