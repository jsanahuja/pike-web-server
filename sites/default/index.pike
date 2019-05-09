<html>
	<head>
		<title>Default XS Page</title>
	</head>
	<body>
		<div id="header">
		</div>
		<div id="content">
			<h1>Default XS Page</h1>
		</div>
		<div><?pike int i = 0; string j = "1"; ?><div id="section">
			<?pike 
				write("This is i %d and this is j %s", i, j); 
			?>
			<?pike write("hello"); ?>
		</div>
	</body>
</html>
