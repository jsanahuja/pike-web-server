#define PORT 80
#define MTU 4096

import ".";
import Utils;
import JSON;

Protocols.HTTP.Server.Port server;
mapping(string:mixed) config = ([
   "error_log": "logs/error.log",
   "access_log": "logs/access.log"
]);

string get_thread_status(Thread.Thread thread){
   int status = thread->status();
   switch(status){
      case Thread.THREAD_NOT_STARTED:
         return "not started";
         break;
      case Thread.THREAD_RUNNING:
         return "running";
         break;
      case Thread.THREAD_EXITED:
         return "exited";
         break;
      // -- not defined (?) --
      // case Thread.THREAD_ABORTED:
         // return "aborted";
         // break;
      default:
         return "unknown";
         break;
   }
}

void load_config(){
   mixed error = catch{
      config = JSON.decode(Stdio.read_file("server.config.json"));
   };
   if(error){
      log_internal("Unable to parse server.config.json. Check file permissions, ownership and JSON format.");
      exit(1);
   }
   if(!has_index(config, "sites_path") || !stringp(config->sites_path) || !Stdio.exist(config->sites_path)){
      log_internal("No sites_path defined in config file");
      exit(2);
   }
   if(!has_index(config, "sites") || !arrayp(config->sites) || sizeof(config->sites) == 0){
      log_internal("No sites defined in config file");
      exit(3);
   }

   foreach(config->sites; int key; mapping(string:mixed) site){
      if(!has_index(site, "path") || !stringp(site->path)){
         log_internal(sprintf("Site path for site #%d is not properly defined", key));
         exit(4);
      }
      if(!Stdio.exist(config->sites_path + site->path)){
         log_internal("Site path could not be found: "+ config->sites_path + site->path);
         exit(5);
      }
   }
}

int main(int argc, array(string) argv){
   //Ctrl+C
   signal(signum("SIGINT"), lambda(int sig){
      write("SIGNAL CAUGHT: "+ signame(sig) + "\n");
      foreach(Thread.all_threads(); int id; Thread.Thread thread){
         write("CLI:%d:KILL: Closing socket and killing thread... (status:%s)\n", id, get_thread_status(thread));
         thread->kill();
         if(thread->status == Thread.THREAD_RUNNING)
            thread->wait();
      }
      if(server){
         server->close();
      }
      exit(1);
   });


   load_config();
   server = Protocols.HTTP.Server.Port(accept_connection, PORT);
   return - 1;
}

void accept_connection(Protocols.HTTP.Server.Request request){
   Thread.Thread thread = Thread.Thread(service_worker, request);
}

void service_worker(Protocols.HTTP.Server.Request request){
   int code;
   mixed time = gauge{
      code = process_request(request);
   };
   write("%d:%s (%f)\n", code, request->request_raw, time);
   log_access("", code, request, time);
}

mapping(string:mixed) resolve_host(string host){
   //Iterating over sites
   foreach(config->sites, mapping(string:mixed) site){
      
      //Iterating over site domains
      if(has_index(site, "domains") && arrayp(site->domains) && sizeof(site->domains) > 0){
         foreach(site->domains, string domain){
            if(domain == host){
               return site;
            }
         }
      }
   }
   return config->sites[0];
}

int process_request(Protocols.HTTP.Server.Request request){
   //Resolve site
   mapping(string:mixed) site = resolve_host(request->request_headers->host);

   //Applying rewrites
   string route = request.not_query;
   if(has_index(site, "rewrites") && mappingp(site->rewrites) && has_index(site->rewrites, route)){
      route = site->rewrites[route];
   }

   //Parsing POST variables over uncommon content-types
   if(!has_index(request->request_headers, "content-type")){
      request->request_headers["content-type"] = "application/xml";
   }
   if(request->request_type == "POST" && strlen(request->body_raw) > 0){
      mapping(string:mixed) vars = ([]);

      switch(request->request_headers["content-type"]){
         case "application/json":
            mixed error = catch{
               vars = JSON.decode(request->body_raw);
            };
            break;
         case "application/xml":
            break;
         case "application/x-www-form-urlencoded":
            //already parsed by pike
            break;
         default:
            log_internal("Unknown content type:" + request->request_headers["content-type"]);
            break;
      }
      request->variables |= vars;
   }


   string path = config->sites_path + site->path;
   path = has_suffix(path, "/") ? path + route : path + "/" + route;

   //Requested a file. Serving...
   if(Stdio.exist(path) && Stdio.is_file(path)){
      return serve(request, path);
   }

   //Requested a folder. Trying to serve a default file (config->defaults).
   if(Stdio.exist(path) && has_index(site, "defaults") && arrayp(site->defaults)){
      //adding the final "/" if not present
      path = has_suffix(path, "/") ? path : path + "/";

      //looking for default files
      foreach(site->defaults, string file){
         if(Stdio.exist(path + file) && Stdio.is_file(path + file)){
            return serve(request, path + file);
         }
      }
   }
   
   //Path exists but unable to serve anything: Permission denied
   if(Stdio.exist(path)){
      return response_503(request);
   }

   //Path not found
   return response_404(request);
}

int serve(Protocols.HTTP.Server.Request request, string file){
   string ext = Array.pop(file / ".")[0];
   if(ext != "pike"){
      return serve_static(request, file);
   }else{
      return serve_pike(request, file);
   }
}

int serve_static(Protocols.HTTP.Server.Request request, string file){
   string ext = Array.pop(file / ".")[0];
   request->response_and_finish(([
      "file": Stdio.File(file),
      "type": Protocols.HTTP.Server.extension_to_type(ext)
   ]));
   return 200;
}

string preprocess_program(string file){
   string result = "";
   result += "void main(function write, mapping request){";
   string data = Stdio.read_file(file);
   data = replace(data, "\r",   "");
   data = replace(data, "\n",   "");
   data = replace(data, "<?pike",   "||--");
   data = replace(data, "?>",       "--||");

   array(string) parts = data / "||";

   foreach(parts, string part){
      if(has_prefix(part, "--") && has_suffix(part, "--")){
         result += replace(part, "--", "");
      }else{
         result += "write(\""+ replace(part, "\"", "\\\"") +"\");";
      }
   }
   result += "}"; 
   return result;
}

int serve_pike(Protocols.HTTP.Server.Request request, string file){
   string code = preprocess_program(file);
   string output = "";
   mixed error1, error2, error3;
   program p;
   mapping(string:mixed) request_data = ([
      "server": ([
         "HTTP_PATH_REQUEST": request->not_query,
         "HTTP_URI_REQUEST": request->full_query
      ]),
      "variables": request->variables
   ]);
   foreach(request->request_headers; string key; mixed value){
      request_data->server["HTTP_" + replace(upper_case(key), "-", "_")] = value;
   }

   error1 = catch{
      p = compile_string(code);
   };

   function buffer = lambda(string|array(string) arg, mixed ... extra){
      mixed e = catch{
         output += sprintf(arg, @extra);
      };
      if(e)
         error2 = e;
   };

   error3 = catch{
      p()->main(buffer, request_data);
   };

   if(error1 || error2 || error3){
      string reason;
      if(error1){
         reason = "Compile error";
      }else if(error2){
         reason = "Parsing error";
      }else if(error3){
         reason = "Execution error";
      }
      return reponse_500(request, reason);
   }else{
      request->response_and_finish(([
         "data": output,
         "type": "text/html",
         "length": strlen(output)
      ]));
      return 200;
   }
}

int reponse_500(Protocols.HTTP.Server.Request request, string reason){
   string response = replace(Stdio.read_file("errors/500.html"), "__reason__", reason);
   request->response_and_finish(([
      "data": response,
      "type": "text/html",
      "length": strlen(response),
      "error": 500
   ]));
   return 500;
}

int response_503(Protocols.HTTP.Server.Request request){
   string response = replace(Stdio.read_file("errors/503.html"), "__route__", request.full_query);
   request->response_and_finish(([
      "data": response,
      "type": "text/html",
      "length": strlen(response),
      "error": 404
   ]));
   return 503;
}

int response_404(Protocols.HTTP.Server.Request request){
   string response = replace(Stdio.read_file("errors/404.html"), "__route__", request.full_query);
   request->response_and_finish(([
      "data": response,
      "type": "text/html",
      "length": strlen(response),
      "error": 404
   ]));
   return 404;
}


/*******************************************************************************************************/
/*                                                                                                     */
/* LOGGER                                                                                              */
/*                                                                                                     */
/*******************************************************************************************************/

void log_internal(string error){
   write(error);
   Stdio.append_file(
      config->error_log,
      sprintf("%s:ERROR: %s\n", get_date(), error)
   );
}

void log_access(string ip, int code, Protocols.HTTP.Server.Request request, mixed time){
   Stdio.append_file(
      config->access_log,
      sprintf("%s:%s:%d: %s %s ( %O ms)\n", get_date(), ip, code, request->protocol, request->full_query, time)
   );
}

void log_error(string ip, int code, string error){
   Stdio.append_file(
      config->error_log,
      sprintf("%s:%s:ERROR: %d %s\n", get_date(), ip, code, error)
   );
}

void log_warning(string ip, string warning){
   Stdio.append_file(
      config->error_log,
      sprintf("%s:%s:WARN: %s\n", get_date(), ip, warning)
   );
}

string get_date(){
   function two_digits = lambda(int num){
      return num < 10 ? "0" + num : "" + num;
   };
   mapping(string:int) date = gmtime(time());
   return sprintf(
      "%d-%s-%s:%s:%s:%s",
      date->year+1900,
      two_digits(date->mon+1),
      two_digits(date->mday),
      two_digits(date->hour),
      two_digits(date->min),
      two_digits(date->sec)
   );
}