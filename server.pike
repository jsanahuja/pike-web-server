#define PORT 80
#define MTU 4096
#define APP_PATH "app"

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
   };
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
   mapping(string:int|string) result;
   mixed time = gauge{
      result = process_request(request);
   };
   write("%s %s (%f)\n", result["path"], request->full_query, time);
   log_access("", result["code"], request, time);
}

mapping(string:int|string) process_request(Protocols.HTTP.Server.Request request){
   string path = APP_PATH + request.not_query;
   if(Stdio.exist(path)){
      if(Stdio.is_file(path)){
         serve_file(request, path);
         return ([ "path": path, "code":200 ]);
      }else{
         path = has_suffix(path, "/") ? path : path + "/";
         if(has_index(config, "defaults") && arrayp(config->defaults)){
            foreach(config->defaults, string file){
               if(Stdio.is_file(path + file)){
                  serve_file(request, path + file);
                  return ([ "path": path+file, "code":200 ]);
               }
            }
         }
      }

      response_503(request);
      return ([ "path": path, "code": 503 ]);
   }

   response_404(request);
   return ([ "path": path, "code": 404 ]);
}

void serve_file(Protocols.HTTP.Server.Request request, string file){
   string ext = Array.pop(file / ".")[0];

   if(ext != "pike"){
      request->response_and_finish(([
         "file": Stdio.File(file),
         "type": Protocols.HTTP.Server.extension_to_type(ext)
      ]));
   }else{
      request->response_and_finish(([
         "data": "no pike processor implemented yet",
         "type": "text/plain",
         "length": strlen("no pike processor implemented yet")
      ]));
   }
}

void reponse_500(Protocols.HTTP.Server.Request request, string reason){
   string response = replace(Stdio.read_file("errors/500.html"), "__reason__", reason);
   request->response_and_finish(([
      "data": response,
      "type": "text/html",
      "length": strlen(response),
      "error": 500
   ]));
}

void response_503(Protocols.HTTP.Server.Request request){
   string response = replace(Stdio.read_file("errors/503.html"), "__route__", request.full_query);
   request->response_and_finish(([
      "data": response,
      "type": "text/html",
      "length": strlen(response),
      "error": 404
   ]));
}

void response_404(Protocols.HTTP.Server.Request request){
   string response = replace(Stdio.read_file("errors/404.html"), "__route__", request.full_query);
   request->response_and_finish(([
      "data": response,
      "type": "text/html",
      "length": strlen(response),
      "error": 404
   ]));
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