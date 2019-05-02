#define PORT 80
#define MTU 4096
#define APP_STATICS "app/statics"
#define APP_PATH "app"

import ".";
import Utils;
import JSON;
import MimeTypes;

Protocols.HTTP.Server.Port server;
int index = 0;

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

   server = Protocols.HTTP.Server.Port(accept_connection, PORT);
   return - 1;
}

void accept_connection(Protocols.HTTP.Server.Request request){
   Thread.Thread thread = Thread.Thread(service_worker, request);
}

void service_worker(Protocols.HTTP.Server.Request request){
   /*
   * protocol     HTTP/1.1
   * request_type GET
   * query        a=1&b=2
   * not_query    /asdg
   * full_query   /asdg?a=1&b=2
   * request_headers Mapping k:v
   */
   string ip = "Unknown";

   /** config parse **/
   mixed config;
   mixed error = catch{
      config = JSON.decode(Stdio.read_file("config.json"));
   };
   if(error){
      reponse_500(request, "Sowe is misconfigured. If you're the owner, please check the logs for more info.");
      log_access(ip, 500, request->protocol, request->full_query);
      log_error(ip, 500, "Wrong config.json JSON format");
      return;
   };

   /** routing **/
   /*** static files ***/
   if(file_exists(APP_STATICS + request.not_query)){
      log_access(ip, 200, request->protocol, request->full_query);
      serve_file(request, APP_STATICS + request.not_query);
      return;
   }
   /*** defined routing ***/
   if(has_index(config, "sections") && mappingp(config->sections)){
      foreach(config->sections; string key; mapping(string:mixed) section){
         if(has_index(section, "paths") && arrayp(section->paths)){
            foreach(section->paths, string path){
               if(request.not_query == path){

                  string layout = "__header____content____footer__", 
                     header = "", 
                     template = "", 
                     footer = "",
                     title = "";

                  if(has_index(section, "layout") && stringp(section->layout) && file_exists(APP_PATH +"/"+ section->layout)){
                     layout = Stdio.read_file(APP_PATH +"/"+ section->layout);
                  }else{
                     layout = "__header____content____footer__";
                  }

                  if(has_index(section, "header") && stringp(section->header) && file_exists(APP_PATH +"/"+ section->header)){
                     header = Stdio.read_file(APP_PATH +"/"+ section->header);
                  }
                  
                  if(has_index(section, "template") && stringp(section->template) && file_exists(APP_PATH +"/"+ section->template)){
                     template = Stdio.read_file(APP_PATH +"/"+ section->template);
                  }
                  
                  if(has_index(section, "footer") && stringp(section->footer) && file_exists(APP_PATH +"/"+ section->footer)){
                     footer = Stdio.read_file(APP_PATH +"/"+ section->footer);
                  }

                  if(has_index(section, "title") && stringp(section->title)){
                     title = section->title;
                  }else{
                     log_warning(ip, sprintf("No title defined for the section %s", key));
                  }

                  
                  string response = layout;
                  response = replace(response, "__title__", title);
                  response = replace(response, "__header__", header);
                  response = replace(response, "__content__", template);
                  response = replace(response, "__footer__", footer);
                  
                  request->response_and_finish(([
                     "data": response,
                     "type": "text/html",
                     "length": strlen(response)
                  ]));
                  log_access(ip, 200, request->protocol, request->full_query);
                  return;
               }
            }
         }else{
            log_warning(ip, sprintf("The section %s has no defined paths", key));
         }
      }
   }else{
      log_warning(ip, "No sections defined in the config.json configuration file.");
   }
   
   log_access(ip, 404, request->protocol, request->full_query);
   response_404(request, request.full_query);
}

bool file_exists(string file){
   bool opened = false;
   catch{
      Stdio.File f = Stdio.File(file, "r");
      if(f)
         opened = true;
   };
   return opened;
}

void serve_file(Protocols.HTTP.Server.Request request, string file){
   string content = Stdio.read_file(file),
   ext = Array.pop(file / ".")[0];

   request->response_and_finish(([
      "data": content,
      "type": MimeTypes.list[ext],
      "length": strlen(content)
   ]));
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

void response_404(Protocols.HTTP.Server.Request request, string route){
   string response = replace(Stdio.read_file("errors/404.html"), "__route__", route);
   
   request->response_and_finish(([
      "data": response,
      "type": "text/html",
      "length": strlen(response),
      "error": 404
   ]));
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

void log_access(string ip, int code, string protocol, string route){
   write(sprintf("%s:  %d %s %s \t\t\t %s \n", get_date(), code, protocol, route, ip));
   Stdio.append_file(
      "logs/access.log",
      sprintf("%s:%s %s %d %s\n", get_date(), ip, protocol, code, route)
   );
}

void log_error(string ip, int code, string error){
   Stdio.append_file(
      "logs/error.log",
      sprintf("%s:%s Error %d - %s\n", get_date(), ip, code, error)
   );
}

void log_warning(string ip, string warning){
   Stdio.append_file(
      "logs/error.log",
      sprintf("%s:%s Warning - %s\n", get_date(), ip, warning)
   );
}