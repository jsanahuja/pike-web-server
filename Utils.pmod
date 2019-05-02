
string|void print_r(mixed item, int|void deep){
    string  result = "", 
            type = basetype(item), 
            elements = "",
            ldisplace = "",
            displace = "\t";

    deep = zero_type(deep) ? 0 : deep;
    for(int i = 0; i < deep; i++){
        ldisplace += "\t";
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
                elements += sprintf("\n%s%s => %s", displace, (string) index, print_r(item[index], deep+1));
            }        
            result += sprintf("Object (%s\n%s)", elements, ldisplace);
            break;
        case "array":
            foreach(item; int key; mixed subitem){
                elements += sprintf("\n%s%d => %s", displace, key, print_r(subitem, deep+1));
            }
            result += sprintf("Array (%s\n%s)", elements, ldisplace);
            break;
        case "mapping":
            foreach(item; mixed key; mixed subitem){
                elements += sprintf("\n%s%s => %s", displace, print_r(key, deep+1), print_r(subitem, deep+1));
            }
            result += sprintf("Mapping (%s\n%s)", elements, ldisplace);
            break;
        case "multiset":
            foreach(item; mixed key; mixed subitem){
                elements += sprintf("\n%s%s => %s", displace, print_r(key, deep+1), print_r(subitem, deep+1));
            }
            result += sprintf("Multiset (%s\n%s)", elements, ldisplace);
            break;
        case "string":
            result += sprintf("\"%s\" (string)", item);
            break;
        case "int":
            result += sprintf("\"%d\" (int)", item);
            break;
        default:
            result += sprintf("Undefined type %s\n", type);
            // result += sprintf("%s (%s)", (string) item, type);
            break;
    }

    //output
    if(deep == 0){
        write(result + "\n");
    }else{
        return result;
    }
}
