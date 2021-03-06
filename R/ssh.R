#' Open a cloud SSH browser for an instance
#' 
#' This will open an SSH from the browser session if \code{getOption("browser")} is not NULL
#' 
#' You will need to login the first time with an email that has access to the instance.
#' 
#' @seealso \url{https://cloud.google.com/compute/docs/ssh-in-browser}
#' 
#' @param instance the instance resource
#' 
#' @return Opens a browser window to the SSH session, returns the SSH URL.
#' @importFrom utils browseURL
#' @export
#' @family ssh functions
gce_ssh_browser <- function(instance){
  
  instance <- as.gce_instance(instance)
  pz <- gce_extract_projectzone(instance)
  
  ssh_url <- sprintf("https://ssh.cloud.google.com/projects/%s/zones/%s/instances/%s?projectNumber=%s",
                     pz$project, pz$zone, as.gce_instance_name(instance), pz$project)
  
  if(!is.null(getOption("browser"))){
    utils::browseURL(ssh_url)
  }

  ssh_url
  
}

#' Remotely execute ssh code, upload & download files.
#' 
#' @description 
#' Assumes that you have ssh & scp installed.  If on Windows see website for workarounds. 
#' 
#' @details 
#' 
#' Only works connecting to linux based instances.
#' 
#' On Windows you will need to install an ssh command line client.
#' 
#' You will need to generate a new SSH key-pair if you have not connected to the instance before via say the gcloud SDK.
#' 
#' To customise SSH connection see \link{gce_ssh_addkeys}
#' 
#' Otherwise, instructions for generating SSH keys can be found here: \url{https://cloud.google.com/compute/docs/instances/connecting-to-instance}.
#'
#' Uploads and downloads are recursive, so if you specify a directory,
#' everything inside the directory will also be downloaded.
#' 
#' @inheritParams gce_ssh_setup
#' @param ... Shell commands to run. Multiple commands are combined with
#'   \code{&&} so that execution will halt after the first failure.
#' @param local,remote Local and remote paths.
#' @param overwrite If TRUE, will overwrite the local file if exists.
#' @param verbose If TRUE, will print command before executing it.
#' @param wait Whether then SSH output should be waited for or run it asynchronously.
#' @param capture_text whether to return the output of the SSH command into an R text
#' 
#' @seealso \url{https://cloud.google.com/compute/docs/instances/connecting-to-instance}
#' @return If capture_text is TRUE, the text of the SSH command result.
#' 
#' 
#' @examples 
#' 
#' \dontrun{
#'   
#'   library(googleComputeEngineR)
#'   
#'   vm <- gce_vm("my-instance")
#'   
#'   ## if you have already logged in via gcloud, the default keys will be used
#'   ## no need to run gce_ssh_addkeys
#'   ## run command on instance            
#'   gce_ssh(vm, "echo foo")
#'   
#'   
#'   ## if running on Windows, use the RStudio default SSH client
#'   ## e.g. add C:\Program Files\RStudio\bin\msys-ssh-1000-18 to your PATH
#'   ## then run: 
#'   vm2 <- gce_vm("my-instance2")
#' 
#'   ## add SSH info to the VM object
#'   ## custom info
#'   vm <- gce_ssh_setup(vm,
#'                       username = "mark", 
#'                       key.pub = "C://.ssh/id_rsa.pub",
#'                       key.private = "C://.ssh/id_rsa")
#'                       
#'   ## run command on instance            
#'   gce_ssh(vm, "echo foo")
#'   #> foo
#' 
#'   ## example to check logs of rstudio docker container
#'   gce_ssh(vm, "sudo journalctl -u rstudio")
#' 
#' }
#' 
#' @export
#' @family ssh functions
gce_ssh <- function(instance, 
                    ..., 
                    key.pub = NULL,
                    key.private = NULL,
                    wait = TRUE,
                    capture_text = FALSE,
                    username = Sys.info()[["user"]]) {
  
  stopifnot(is.gce_instance(instance))
  
  instance <- gce_ssh_setup(instance = instance, 
                            username = username,
                            key.pub = key.pub,
                            key.private = key.private)
  
  username <- instance$ssh$username
  
  lines <- paste(c(...), collapse = " \\\n&& ")
  if (lines == "") stop("Provide commands", call. = FALSE)

  if(capture_text) {
    # Assume that the remote host uses /tmp as the temp dir, and is unix based
    temp_remote <- paste0("/tmp/gce_cmd", idempotency())
    temp_local <- tempfile("gcer_cmd")
    on.exit(unlink(temp_local))
    
    cmd <- paste0(
      "ssh ", ssh_options(instance),
      " ", username, "@", gce_get_external_ip(instance, verbose = FALSE),
      " ", shQuote(paste(lines, ">", temp_remote))
    )
    
    do_system(instance, cmd, wait = wait)
    gce_ssh_download(instance, temp_remote, temp_local)

    out <- readLines(temp_local, warn = FALSE)
    
  } else {
    
    cmd <- paste0(
      "ssh ", ssh_options(instance),
      " ", username, "@", gce_get_external_ip(instance, verbose = FALSE),
      " ", shQuote(lines)
    )
    
    out <- do_system(instance, cmd, wait = wait)
    
  }
  
  out
}

#' @export
#' @rdname gce_ssh
gce_ssh_upload <- function(instance,
                           local, 
                           remote, 
                           username = Sys.info()[["user"]], 
                           key.pub = NULL,
                           key.private = NULL,
                           verbose = FALSE,
                           wait = TRUE) {

  stopifnot(is.gce_instance(instance))
  
  instance <- gce_ssh_setup(instance = instance, 
                            username = username,
                            key.pub = key.pub,
                            key.private = key.private)
  
  username <- instance$ssh$username
  
  cmd <- paste0(
    "scp -r ", ssh_options(instance),
    " ", local,
    " ", username, "@", gce_get_external_ip(instance, verbose = FALSE), ":", remote
  )

  do_system(instance, cmd, wait = wait)
}

#' @export
#' @rdname gce_ssh
gce_ssh_download <- function(instance,
                             remote, 
                             local, 
                             username = Sys.info()[["user"]], 
                             key.pub = NULL,
                             key.private = NULL,
                             verbose = FALSE, 
                             overwrite = FALSE,
                             wait = TRUE) {

  stopifnot(is.gce_instance(instance))
  
  instance <- gce_ssh_setup(instance = instance, 
                            username = username,
                            key.pub = key.pub,
                            key.private = key.private)
  
  username <- instance$ssh$username
  
  local <- normalizePath(local, mustWork = FALSE)

  if (file.exists(local) && file.info(local)$isdir) {
    # If `local` exists and is a dir, then just put the result in that directory
    local_dir <- local
    need_rename <- FALSE

  } else {
    # If `local` isn't an existing directory, put the result in the parent
    local_dir <- dirname(local)
    need_rename <- TRUE
  }

  # A temp dir for the downloaded file(s)
  local_tempdir <- tempfile("download", local_dir)
  local_tempfile <- file.path(local_tempdir, basename(remote))

  if (need_rename) {
    # Rename to local name
    dest <- file.path(local_dir, basename(local))
  } else {
    # Keep original name
    dest <- file.path(local_dir, basename(remote))
  }

  if (file.exists(dest) && !overwrite) {
    stop("Destination file already exists.")
  }

  external_ip <- gce_get_external_ip(instance, verbose = FALSE)

  dir.create(local_tempdir)
  # Rename the downloaded files when we exit
  on.exit({
    if (file.exists(dest)) unlink(dest, recursive = TRUE)
    file.rename(local_tempfile, dest)
    unlink(local_tempdir, recursive = TRUE)
  })
  
  ## original that works on local unix based systems
  if(.Platform$OS.type != "windows"){
    
    # This ssh's to the remote machine, tars the file(s), and sends it to the
    # local host where it is untarred.
    cmd <- paste0(
      "ssh ", ssh_options(instance),
      " ", username, "@", external_ip, " ",
      sprintf("'cd %s && tar cz %s'", dirname(remote), basename(remote)),
      " | ",
      sprintf("(cd %s && tar xz)", local_tempdir)
    )
    
  } else {
    
    ## if on Windows no untarring as tar isn't on Windows (#35)
    cmd <- paste0(
      "ssh ", ssh_options(instance),
      " ", username, "@", external_ip, " ",
      " > ",
      shQuote(local_tempfile)
    )
  }

  do_system(instance, cmd, wait = wait)
}


do_system <- function(instance, 
                      cmd,  
                      wait = TRUE
                      ) {
  
  stopifnot(is.gce_instance(instance))
  
  cli_tools()
  external_ip <- gce_get_external_ip(instance, verbose = FALSE)
  # check to make sure port 22 open, otherwise ssh commands will fail
  if (!is_port_open(external_ip, 22)) {
    stop("port 22 is not open for ", external_ip, call. = FALSE)
  }
  myMessage(cmd, level = 2)
  
  status <- system(cmd, wait = wait)
  if (status != 0) {
    stop("ssh failed\n", cmd, call. = FALSE)
  }

  invisible(TRUE)
}