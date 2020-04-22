# abstract base class for schedule, not exported
setClass("schedule", contains = "VIRTUAL")


### SCHEDULE LOCAL CLASS
#' Schedule seaMass to run locally
#'
#' @export schedule_local
schedule_local <- setClass("schedule_local", contains = "schedule")


#' @include generics.R
setMethod("prepare_sigma", "schedule_local", function(object, sigma) {
  return(invisible(object))
})


#' @include generics.R
setMethod("prepare_delta", "schedule_local", function(object, delta) {
  return(invisible(object))
})


#' @include generics.R
setMethod("run", "schedule_local", function(object, sigma) {
  ctrl <- control(sigma)

  cat(paste0("[", Sys.time(), "]  running name=", name(sigma), "...\n"))

  for (fit in fits(sigma)) {
    # run empirical bayes process0
    for (chain in 1:ctrl@model.nchain) process0(fit, chain)

    # run full process1
    for (chain in 1:ctrl@model.nchain) process1(fit, chain)

    # run plots if you want
    if (length(ctrl@plots) > 0) for (chain in 1:ctrl@model.nchain) plots(fit, chain)
  }

  # run delta if they exist
  for (delta in open_seaMass_deltas(sigma, force = T)) run(delta)

  # finish
  finish(sigma)

  return(invisible(object))
})


### SCHEDULE SLURM CLASS
#' Schedule seaMass to run on SLURM
#'
#' @export schedule_slurm
setClass("schedule_slurm", contains = "schedule", slots = c(
  submit.prefix = "character",
  partition = "character",
  cpus_per_task = "integer",
  mem = "character",
  time = "character",
  mail_user = "character"
))


#' @describeIn schedule_slurm-class Generator function
#' @param partition .
#' @param time .
#' @param mem .
#' @param nthread .
#' @param mail_user .
#' @export schedule_slurm
schedule_slurm <- function(
  submit.prefix = "",
  partition = NULL,
  cpus_per_task = NULL,
  mem = NULL,
  time = NULL,
  mail_user = NULL
) {
  params <- list("schedule_slurm")

  params$submit.prefix <- as.character(submit.prefix)
  if (is.null(partition)) params$partition <- NA_character_ else params$partition <- as.character(partition)
  if (is.null(cpus_per_task)) params$cpus_per_task <- NA_integer_ else params$cpus_per_task <- as.integer(cpus_per_task)
  if (is.null(time)) params$time <- NA_character_ else params$time <- as.character(time)
  if (is.null(mem)) params$mem <- NA_character_ else params$mem <- as.character(mem)
  if (is.null(mail_user)) params$mail_user <- NA_character_ else params$mail_user <- as.character(mail_user)

  return(do.call(new, params))
}


setValidity("schedule_slurm", function(object) {
  if (length(object@submit.prefix) != 1) return("'submit.prefix' must be a string!")
  if (!(length(object@cpus_per_task) == 1 &&  (is.na(object@cpus_per_task) || object@cpus_per_task > 0))) return("'cpus_per_task' must be a positive scalar!")
  if (length(object@partition) != 1) return("'partition' must be a string!")
  if (length(object@time) != 1) return("'time' must be a string!")
  if (length(object@mem) != 1) return("'mem' must be a string!")
  if (length(object@mail_user) != 1) return("'mail_user' must be a string!")

  return(T)
})


#' @include generics.R
setMethod("config", "schedule_slurm", function(object, prefix, name, n, notify, func) {
  return(paste0(
    "#!/bin/bash\n",
    paste0("#SBATCH --job-name=sm", prefix, ".", name, "\n"),
    paste0("#SBATCH --output=sm", prefix, ".", name, "-%A_%a.out\n"),
    paste0("#SBATCH --error=sm", prefix, ".", name, "-%A_%a.err\n"),
    paste0("#SBATCH --array=1-", n, "\n"),
    ifelse(is.na(object@partition), "", paste0("#SBATCH --partition=", object@partition, "\n")),
    "#SBATCH --nodes=1\n",
    "#SBATCH --ntasks-per-node=1\n",
    ifelse(is.na(object@cpus_per_task), "", paste0("#SBATCH --cpus-per-task=", object@cpus_per_task, "\n")),
    ifelse(is.na(object@mem), "", paste0("#SBATCH --mem=", object@mem, "\n")),
    ifelse(is.na(object@time), "", paste0("#SBATCH --time=", object@time, "\n")),
    ifelse(is.na(object@mail_user), "", paste0("#SBATCH --mail-user=", object@mail_user, "\n")),
    ifelse(is.na(object@mail_user), "", ifelse(notify, "#SBATCH --mail-type=END,FAIL\n", "#SBATCH --mail-type=FAIL\n")),
    paste0("srun Rscript --vanilla -e seaMass:::", func, "\\(${SLURM_ARRAY_TASK_ID}\\)\n")
  ))
})


#' @include generics.R
setMethod("prepare_sigma", "schedule_slurm", function(object, sigma) {
  name <- name(sigma)
  ctrl <- control(sigma)
  n <- length(fits(sigma)) * ctrl@model.nchain

  cat(config(object, "0", name, n, F, "hpc_process0"), file = file.path(sigma@path, "submit.process0"))
  cat(config(object, "1", name, n, F, "hpc_process1"), file = file.path(sigma@path, "submit.process1"))
  if (length(ctrl@plots) > 0) cat(config(object, "P", name, n, F, "hpc_plots"), file = file.path(sigma@path, "submit.plots"))
  cat(config(object, "", name, 1, T, "hpc_finish"), file = file.path(sigma@path, "submit.finish"))

  # submit script
  cat(paste0(
    "#!/bin/bash\n",
    "DIR=\"$( cd \"$( dirname \"${BASH_SOURCE[0]}\" )\" && pwd )\"\n",
    "pushd $DIR > /dev/null\n",
    "\n",
    "# job chain\n",
    "JOBID=$(sbatch --parsable submit.process0)\n",
    "EXITCODE=$?\n",
    "PROCESS0=$JOBID\n",
    "\n",
    "JOBID=$(sbatch --parsable --dependency=afterok:$JOBID submit.process1)\n",
    "EXITCODE=$?\n",
    "PROCESS1=$JOBID\n",
    "\n",
    "if [ -e \"submit.plots\" ]; then\n",
    "  JOBID=$(sbatch --parsable --dependency=afterok:$JOBID submit.plots)\n",
    "  EXITCODE=$?\n",
    "  PLOTS=$JOBID\n",
    "fi\n",
    "\n",
    "if [ -e \"submit.delta\" ]; then\n",
    "  JOBID=$(sbatch --parsable --dependency=afterok:$JOBID submit.delta)\n",
    "  EXITCODE=$?\n",
    "  DELTA=$JOBID\n",
    "fi\n",
    "\n",
    "JOBID=$(sbatch --parsable --dependency=afterok:$JOBID submit.finish)\n",
    "EXITCODE=$?\n",
    "finish=$JOBID\n",
    "\n",
    "# clean up\n",
    "if [[ $EXITCODE != 0 ]]; then\n",
    "  scancel $PROCESS0 $PROCESS1 $PLOTS $DELTA $finish \n",
    "  echo Failed to submit jobs!\n",
    "else\n",
    "  echo Submitted jobs! To cancel execute $DIR/cancel.sh\n",
    "  echo '#!/bin/bash' > $DIR/cancel.sh\n",
    "  echo scancel $PROCESS0 $PROCESS1 $PLOTS $DELTA $finish >> $DIR/cancel.sh\n",
    "  chmod u+x $DIR/cancel.sh\n",
    "fi\n",
    "\n",
    "popd > /dev/null\n",
    "exit $EXITCODE\n"
  ), file = file.path(sigma@path, "submit.sh"))
  system(paste("chmod u+x", file.path(sigma@path, "submit.sh")))

  return(invisible(object))
})


#' @include generics.R
setMethod("prepare_delta", "schedule_slurm", function(object, delta) {
  cat(config(object, "D", name(delta@sigma), length(open_seaMass_deltas(delta@sigma, force = T)), F, "hpc_delta"), file = file.path(delta@sigma@path, "submit.delta"))
  return(invisible(object))
})


#' @include generics.R
setMethod("run", "schedule_slurm", function(object, sigma) {
  cat(paste0("[", Sys.time(), "]  submitting to SLURM...\n"))
  system(paste0(object@submit.prefix, file.path(basename(path(sigma)), "submit.sh")))
  return(invisible(object))
})


### SCHEDULE PBS CLASS
#' Schedule seaMass to run on PBS
#'
#' @export schedule_pbs
setClass("schedule_pbs", contains = "schedule", slots = c(
  submit.prefix = "character",
  q = "character",
  ppn = "integer",
  mem = "character",
  walltime = "character",
  l = "character",
  M = "character"
))


#' @describeIn schedule_pbs-class Generator function
#' @param q .
#' @param ppn .
#' @param mem .
#' @param walltime .
#' @param M .
#' @export schedule_pbs
schedule_pbs <- function(
  submit.prefix = "",
  q = NULL,
  ppn = NULL,
  mem = NULL,
  walltime = NULL,
  l = NULL,
  M = NULL
) {
  params <- list("schedule_pbs")

  params$submit.prefix <- as.character(submit.prefix)
  if (is.null(q)) params$q <- NA_character_ else params$q <- as.character(q)
  if (is.null(ppn)) params$ppn <- NA_integer_ else params$ppn <- as.integer(ppn)
  if (is.null(walltime)) params$walltime <- NA_character_ else params$walltime <- as.character(walltime)
  if (is.null(mem)) params$mem <- NA_character_ else params$mem <- as.character(mem)
  params$l <- as.character(l)
  if (is.null(M)) params$M <- NA_character_ else params$M <- as.character(M)

  return(do.call(new, params))
}


setValidity("schedule_pbs", function(object) {
  if (length(object@submit.prefix) != 1) return("'submit.prefix' must be a string!")
  if (length(object@q) != 1) return("'q' must be a string!")
  if (!(length(object@ppn) == 1 &&  (is.na(object@ppn) || object@ppn > 0))) return("'ppn' must be a positive scalar!")
  if (length(object@mem) != 1) return("'mem' must be a string!")
  if (length(object@walltime) != 1) return("'walltime' must be a string!")
  if (length(object@M) != 1) return("'M' must be a string!")

  return(T)
})


#' @include generics.R
setMethod("config", "schedule_pbs", function(object, prefix, name, n, notify, func) {
  return(paste0(
    paste0("#PBS -N sm", prefix, ".", name, "\n"),
    paste0("#PBS -t 1-", n, "\n"),
    ifelse(is.na(object@q), "", paste0("#PBS -q ", object@q, "\n")),
    ifelse(is.na(object@ppn), "", paste0("#PBS -l nodes=1:ppn=", object@ppn, "\n")),
    ifelse(is.na(object@mem), "", paste0("#PBS -l mem=", object@mem, "\n")),
    ifelse(is.na(object@walltime), "", paste0("#PBS -l walltime=", object@walltime, "\n")),
    ifelse(length(object@l) == 0, "", paste0(paste0("#PBS -l ", object@l, "\n"), collapse = "")),
    ifelse(is.na(object@M), "", paste0("#PBS -M ", object@M, "\n")),
    ifelse(is.na(object@M), "", ifelse(notify, "#PBS -m ae\n", "#PBS -m a\n")),
    "cd $PBS_O_WORKDIR\n",
    paste0("Rscript --vanilla -e seaMass:::", func, "\\(${PBS_ARRAYID}\\)\n")
  ))
})


#' @include generics.R
setMethod("prepare_sigma", "schedule_pbs", function(object, sigma) {
  name <- name(sigma)
  ctrl <- control(sigma)
  n <- length(fits(sigma)) * ctrl@model.nchain

  cat(config(object, "0", name, n, F, "hpc_process0"), file = file.path(sigma@path, "submit.process0"))
  cat(config(object, "1", name, n, F, "hpc_process1"), file = file.path(sigma@path, "submit.process1"))
  if (length(ctrl@plots) > 0) cat(config(object, "P", name, n, F, "hpc_plots"), file = file.path(sigma@path, "submit.plots"))
  cat(config(object, "", name, 1, T, "hpc_finish"), file = file.path(sigma@path, "submit.finish"))

  # submit script
  cat(paste0(
    "#!/bin/bash\n",
    "DIR=\"$( cd \"$( dirname \"${BASH_SOURCE[0]}\" )\" && pwd )\"\n",
    "pushd $DIR > /dev/null\n",
    "\n",
    "# job chain\n",
    "JOBID=$(qsub submit.process0)\n",
    "EXITCODE=$?\n",
    "PROCESS0=$JOBID\n",
    "\n",
    "JOBID=$(qsub -W depend=afterokarray:$JOBID submit.process1)\n",
    "EXITCODE=$?\n",
    "PROCESS1=$JOBID\n",
    "\n",
    "if [ -e \"submit.plots\" ]; then\n",
    "  JOBID=$(qsub -W depend=afterokarray:$JOBID submit.plots)\n",
    "  EXITCODE=$?\n",
    "  PLOTS=$JOBID\n",
    "fi\n",
    "\n",
    "if [ -e \"submit.delta\" ]; then\n",
    "  JOBID=$(qsub -W depend=afterokarray:$JOBID submit.delta)\n",
    "  EXITCODE=$?\n",
    "  DELTA=$JOBID\n",
    "fi\n",
    "\n",
    "JOBID=$(qsub -W depend=afterokarray:$JOBID submit.finish)\n",
    "EXITCODE=$?\n",
    "finish=$JOBID\n",
    "\n",
    "# clean up\n",
    "if [[ $EXITCODE != 0 ]]; then\n",
    "  qdel $PROCESS0 $PROCESS1 $PLOTS $DELTA $finish \n",
    "  echo Failed to submit jobs!\n",
    "else\n",
    "  echo Submitted jobs! To cancel execute $DIR/cancel.sh\n",
    "  echo '#!/bin/bash' > $DIR/cancel.sh\n",
    "  echo qdel $PROCESS0 $PROCESS1 $PLOTS $DELTA $finish >> $DIR/cancel.sh\n",
    "  chmod u+x $DIR/cancel.sh\n",
    "fi\n",
    "\n",
    "popd > /dev/null\n",
    "exit $EXITCODE\n"
  ), file = file.path(sigma@path, "submit.sh"))
  system(paste("chmod u+x", file.path(sigma@path, "submit.sh")))

  return(invisible(object))
})


#' @include generics.R
setMethod("prepare_delta", "schedule_pbs", function(object, delta) {
  cat(config(object, "D", name(delta@sigma), length(open_seaMass_deltas(delta@sigma, force = T)), F, "hpc_delta"), file = file.path(delta@sigma@path, "submit.delta"))
  return(invisible(object))
})


#' @include generics.R
setMethod("run", "schedule_pbs", function(object, sigma) {
  cat(paste0("[", Sys.time(), "]  submitting to PBS...\n"))
  system(paste0(object@submit.prefix, file.path(basename(path(sigma)), "submit.sh")))
  return(invisible(object))
})


### SCHEDULE SGE CLASS
#' Schedule seaMass to run on SGE
#'
#' @export schedule_pbs
setClass("schedule_sge", contains = "schedule", slots = c(
  submit.prefix = "character",
  q = "character",
  pe = "character",
  mem = "character",
  walltime = "character",
  l = "character",
  M = "character"
))


#' @describeIn schedule_sge-class Generator function
#' @param q .
#' @param pe .
#' @param mem .
#' @param time .
#' @param M .
#' @export schedule_sge
schedule_sge <- function(
  submit.prefix = "",
  q = NULL,
  pe = NULL,
  mem = NULL,
  walltime = NULL,
  l = NULL,
  M = NULL
) {
  params <- list("schedule_sge")

  params$submit.prefix <- as.character(submit.prefix)
  if (is.null(q)) params$q <- NA_character_ else params$q <- as.character(q)
  if (is.null(pe)) params$pe <- NA_character_ else params$pe <- as.character(pe)
  if (is.null(mem)) params$mem <- NA_character_ else params$mem <- as.character(mem)
  if (is.null(walltime)) params$walltime <- NA_character_ else params$walltime <- as.character(walltime)
  params$l <- as.character(l)
  if (is.null(M)) params$M <- NA_character_ else params$M <- as.character(M)

  return(do.call(new, params))
}


setValidity("schedule_sge", function(object) {
  if (length(object@submit.prefix) != 1) return("'submit.prefix' must be a string!")
  if (length(object@q) != 1) return("'q' must be a string!")
  if (length(object@pe) != 1) return("'pe' must be a string!")
  if (length(object@mem) != 1) return("'mem' must be a string!")
  if (length(object@walltime) != 1) return("'walltime' must be a string!")
  if (length(object@M) != 1) return("'M' must be a string!")

  return(T)
})


setMethod("config", "schedule_sge", function(object, prefix, name, n, notify, func) {
  return(paste0(
    paste0("#$ -N sm", prefix, ".", name, "\n"),
    paste0("#$ -t 1-", n, "\n"),
    ifelse(is.na(object@q), "", paste0("#$ -q ", object@q, "\n")),
    ifelse(is.na(object@pe), "", paste0("#$ -pe ", object@pe, "\n")),
    ifelse(is.na(object@mem), "", paste0("#$ -l mem=", object@mem, "\n")),
    ifelse(is.na(object@walltime), "", paste0("#$ -l walltime=", object@walltime, "\n")),
    ifelse(length(object@l) == 0, "", paste0(paste0("#$ -l ", object@l, "\n"), collapse = "")),
    ifelse(is.na(object@M), "", paste0("#$ -M ", object@M, "\n")),
    ifelse(is.na(object@M), "", ifelse(notify, "#$ -m ae\n", "#$ -m a\n")),
    "#$ -cwd\n",
    paste0("Rscript --vanilla -e seaMass:::", func, "\\(${SGE_TASK_ID}\\)\n")
  ))
})


#' @include generics.R
setMethod("prepare_sigma", "schedule_sge", function(object, sigma) {
  name <- name(sigma)
  ctrl <- control(sigma)
  n <- length(fits(sigma)) * ctrl@model.nchain

  cat(config(object, "0", name, n, F, "hpc_process0"), file = file.path(sigma@path, "submit.process0"))
  cat(config(object, "1", name, n, F, "hpc_process1"), file = file.path(sigma@path, "submit.process1"))
  if (length(ctrl@plots) > 0) cat(config(object, "P", name, n, F, "hpc_plots"), file = file.path(sigma@path, "submit.plots"))
  cat(config(object, "", name, 1, T, "hpc_finish"), file = file.path(sigma@path, "submit.finish"))

  # submit script
  cat(paste0(
    "#!/bin/bash\n",
    "DIR=\"$( cd \"$( dirname \"${BASH_SOURCE[0]}\" )\" && pwd )\"\n",
    "pushd $DIR > /dev/null\n",
    "\n",
    "# job chain\n",
    "PROCESS0=$(qsub submit.process0)\n",
    "EXITCODE=$?\n",
    "JOBNAME=submit.process0\n",
    "\n",
    "PROCESS1=$(qsub -hold_jid $JOBNAME submit.process1)\n",
    "EXITCODE=$?\n",
    "JOBNAME=submit.process1\n",
    "\n",
    "if [ -e \"submit.plots\" ]; then\n",
    "  PLOTS=$(qsub -hold_jid $JOBNAME submit.plots)\n",
    "  EXITCODE=$?\n",
    "  JOBNAME=submit.plots\n",
    "fi\n",
    "\n",
    "if [ -e \"submit.delta\" ]; then\n",
    "  DELTA=$(qsub -hold_jid $JOBNAME submit.delta)\n",
    "  EXITCODE=$?\n",
    "  JOBNAME=submit.delta\n",
    "fi\n",
    "\n",
    "finish=$(qsub -hold_jid $JOBNAME submit.finish)\n",
    "EXITCODE=$?\n",
    "\n",
    "# clean up\n",
    "if [[ $EXITCODE != 0 ]]; then\n",
    "  qdel $PROCESS0 $PROCESS1 $PLOTS $DELTA $finish \n",
    "  echo Failed to submit jobs!\n",
    "else\n",
    "  echo Submitted jobs! To cancel execute $DIR/cancel.sh\n",
    "  echo '#!/bin/bash' > $DIR/cancel.sh\n",
    "  echo qdel $PROCESS0 $PROCESS1 $PLOTS $DELTA $finish >> $DIR/cancel.sh\n",
    "  chmod u+x $DIR/cancel.sh\n",
    "fi\n",
    "\n",
    "popd > /dev/null\n",
    "exit $EXITCODE\n"
  ), file = file.path(sigma@path, "submit.sh"))
  system(paste("chmod u+x", file.path(sigma@path, "submit.sh")))

  return(invisible(object))
})


#' @include generics.R
setMethod("prepare_delta", "schedule_sge", function(object, delta) {
  cat(config(object, "D", name(delta@sigma), length(open_seaMass_deltas(delta@sigma, force = T)), F, "hpc_delta"), file = file.path(delta@sigma@path, "submit.delta"))

  return(invisible(object))
})


#' @include generics.R
setMethod("run", "schedule_sge", function(object, sigma) {
  cat(paste0("[", Sys.time(), "]  submitting to SGE...\n"))
  system(paste0(object@submit.prefix, file.path(basename(path(sigma)), "submit.sh")))
  return(invisible(object))
})


hpc_process0 <- function(task) {
  sigma <- open_seaMass_sigma(".", force = T)
  nchain <- control(sigma)@model.nchain
  cat(paste0("[", Sys.time(), "] seaMass-sigma v", control(sigma)@version, "\n"))
  cat(paste0("[", Sys.time(), "]  running process0 for name=", name(sigma), "...\n"))
  process0(fits(sigma)[[(task-1) %/% nchain + 1]], (task-1) %% nchain + 1)
  cat(paste0("[", Sys.time(), "] finished!\n"))
  print(warnings(file = stderr()))

  return(invisible(0))
}


hpc_process1 <- function(task) {
  sigma <- open_seaMass_sigma(".", force = T)
  nchain <- control(sigma)@model.nchain
  cat(paste0("[", Sys.time(), "] seaMass-sigma v", control(sigma)@version, "\n"))
  cat(paste0("[", Sys.time(), "]  running process1 for name=", name(sigma), "...\n"))
  process1(fits(sigma)[[(task-1) %/% nchain + 1]], (task-1) %% nchain + 1)
  cat(paste0("[", Sys.time(), "] finished!\n"))
  print(warnings(file = stderr()))

  return(invisible(0))
}


hpc_plots <- function(task) {
  sigma <- open_seaMass_sigma(".", force = T)
  nchain <- control(sigma)@model.nchain
  cat(paste0("[", Sys.time(), "] seaMass-sigma v", control(sigma)@version, "\n"))
  cat(paste0("[", Sys.time(), "]  running plots for name=", name(sigma), "...\n"))
  plots(fits(sigma)[[(task-1) %/% nchain + 1]], (task-1) %% nchain + 1)
  cat(paste0("[", Sys.time(), "] finished!\n"))
  print(warnings(file = stderr()))

  return(invisible(0))
}


hpc_delta <- function(task) {
  delta <- open_seaMass_deltas(open_seaMass_sigma(".", force = T), force = T)[[task]]
  cat(paste0("[", Sys.time(), "] seaMass-delta v", control(delta)@version, "\n"))
  cat(paste0("[", Sys.time(), "]  running name=", name(delta), "...\n"))
  run(delta)
  cat(paste0("[", Sys.time(), "] finished!\n"))
  print(warnings(file = stderr()))

  return(invisible(0))
}


hpc_finish <- function(task) {
  sigma <- open_seaMass_sigma(".", force = T)
  cat(paste0("[", Sys.time(), "] seaMass-sigma v", control(sigma)@version, "\n"))
  cat(paste0("[", Sys.time(), "]  finishing..."))
  finish(sigma)
  cat(paste0("[", Sys.time(), "] finished!\n"))
  print(warnings(file = stderr()))

  return(invisible(0))
}

