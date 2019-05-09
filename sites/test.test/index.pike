<?pike

string|void print_r(mixed item, int|void deep){
    string  result = "",
        type = basetype(item), 
        elements = "",
        ldisplace = "",
        displace = "&nbsp;&nbsp;&nbsp;&nbsp;",
        FORMAT_EOL = "<br/>";

    deep = zero_type(deep) ? 0 : deep;
    for(int i = 0; i < deep; i++){
        ldisplace += "&nbsp;&nbsp;&nbsp;&nbsp;";
    }
    displace +=ldisplace;

    switch(type){
        case "function":
            result += "function " + function_name(item);
            break;
        case "program":
            result += "program";
            break;
        case "object":
            foreach(indices(item), mixed index){
                elements += sprintf("%s%s%s => %s", FORMAT_EOL, displace, (string) index, print_r(item[index], deep+1));
            }        
            result += sprintf("Object (%s%s%s)", elements, FORMAT_EOL, ldisplace);
            break;
        case "array":
            foreach(item; int key; mixed subitem){
                elements += sprintf("%s%s%d => %s", FORMAT_EOL, displace, key, print_r(subitem, deep+1));
            }
            result += sprintf("Array (%s%s%s)", elements, FORMAT_EOL, ldisplace);
            break;
        case "mapping":
            foreach(item; mixed key; mixed subitem){
                elements += sprintf("%s%s%s => %s", FORMAT_EOL, displace, print_r(key, deep+1), print_r(subitem, deep+1));
            }
            result += sprintf("Mapping (%s%s%s)", elements, FORMAT_EOL, ldisplace);
            break;
        case "multiset":
            foreach(item; mixed key; mixed subitem){
                elements += sprintf("%s%s%s => %s", FORMAT_EOL, displace, print_r(key, deep+1), print_r(subitem, deep+1));
            }
            result += sprintf("Multiset (%s%s%s)", elements, FORMAT_EOL, ldisplace);
            break;
        case "string":
            result += sprintf("\"%s\" (string)", item);
            break;
        case "int":
            result += sprintf("\"%d\" (int)", item);
            break;
        default:
            result += sprintf("Undefined type %s%s", type, FORMAT_EOL);
            break;
    }

    if(deep == 0){
        write(result + FORMAT_EOL);
    }else{
        return result;
    }

};

?>
<html>
	<head>
		<title>Test.test Page!</title>
	</head>
	<body>
		<div id="header">
		</div>
		<div id="content">
			<h1>Default XS Page</h1>
		</div>
		<div><?pike int i = 0; string j = "1"; ?><div id="section">
			<?pike write("hello"); ?>
            <?pike print_r(request); ?>
		</div>
	</body>
</html>
