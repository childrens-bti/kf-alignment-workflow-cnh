cwlVersion: v1.2
class: CommandLineTool
id: fastp_adapter_detect
label: "fastp v1.3.6 Adapter Detection"
doc: |
  Run fastp to detect adapter sequences and produce JSON and HTML QC reports.
  Trimmed reads are discarded (/tmp); only the reports are used downstream.
  Processes up to 1M reads by default.
  - For paired-end input: provide reads2 for separate files, or set interleaved=true for interleaved file.
  - Automatically adds --detect_adapter_for_pe when reads2 is provided or interleaved=true.
  Manual adapters override detected adapters independently for each read end.
  Detected adapters are selected for cutadapt only when fastp annotates the exact
  sequence as a member of its built-in known-adapter pool. Fastp's less-than-1%
  adapter-content warning is informational and does not reject a known adapter.
  De novo or unspecified detections are rejected. Cutadapt runs when at least
  one read end has a manual or known detected adapter.
  Paired-end and interleaved read ends are evaluated independently.
requirements:
  - class: ShellCommandRequirement
  - class: DockerRequirement
    dockerPull: 'quay.io/biocontainers/fastp:1.3.6--h43da1c4_0'
  - class: InlineJavascriptRequirement
  - class: InitialWorkDirRequirement
    listing:
      - entryname: run_fastp
        entry: |
          #!/bin/bash
          set -euo pipefail
          interleaved=false
          input=""
          previous=""
          for arg in "$@"; do
            if [[ "$arg" == "--interleaved_in" ]]; then
              interleaved=true
            elif [[ "$previous" == "-i" ]]; then
              input="$arg"
            fi
            previous="$arg"
          done
          if [[ "$interleaved" == false ]]; then
            exec fastp "$@"
          fi
          threads=""
          reads_to_process=""
          html=""
          json=""
          out1=""
          out2=""
          while [[ "$#" -gt 0 ]]; do
            case "$1" in
              -i) input="$2"; shift 2 ;;
              --thread) threads="$2"; shift 2 ;;
              --reads_to_process) reads_to_process="$2"; shift 2 ;;
              -h) html="$2"; shift 2 ;;
              -j) json="$2"; shift 2 ;;
              -o) out1="$2"; shift 2 ;;
              -O) out2="$2"; shift 2 ;;
              *) shift ;;
            esac
          done
          r1=/tmp/fastp_interleaved_r1.fastq
          r2=/tmp/fastp_interleaved_r2.fastq
          if [[ "$input" == *.gz ]]; then
            gzip -cd -- "$input"
          else
            cat -- "$input"
          fi | awk -v r1="$r1" -v r2="$r2" '{out = (int((NR - 1) / 4) % 2 == 0 ? r1 : r2); print > out}'
          exec fastp -i "$r1" -I "$r2" --thread "$threads" \
            --reads_to_process "$reads_to_process" --detect_adapter_for_pe \
            -h "$html" -j "$json" -o "$out1" -O "$out2"
  - class: ResourceRequirement
    coresMin: $(inputs.threads)
    ramMin: 4000

baseCommand: [bash, run_fastp]

inputs:
  reads1:
    type: File
    doc: "R1 FASTQ (or FASTQ.GZ) file, or interleaved paired-end FASTQ if interleaved=true"
    inputBinding:
      prefix: "-i"
      position: 1
  reads2:
    type: 'File?'
    doc: "R2 FASTQ (or FASTQ.GZ) file for paired-end input (set to null if interleaved=true)"
    inputBinding:
      prefix: "-I"
      position: 2
  interleaved:
    type: 'boolean?'
    default: false
    doc: "Set to true if reads1 contains interleaved paired-end reads"
  sample_name:
    type: string
    doc: "Sample name used to name output reports"
  manual_r1_adapter:
    type: 'string?'
    doc: "User-provided R1 adapter. If present and not 'unspecified', it overrides fastp detection."
  manual_r2_adapter:
    type: 'string?'
    doc: "User-provided R2 adapter. Used with manual_r1_adapter when present; 'unspecified' is treated as empty."
  threads:
    type: 'int?'
    default: 4
    inputBinding:
      prefix: "--thread"
      position: 3
  reads_to_process:
    type: 'int?'
    default: 1000000
    doc: "Limit number of reads analysed (speeds up detection)"
    inputBinding:
      prefix: "--reads_to_process"
      position: 4

arguments:
  - position: 2
    shellQuote: false
    valueFrom: |
      $(inputs.interleaved ? "--interleaved_in" : null)
  - position: 5
    shellQuote: false
    valueFrom: |
      $(inputs.interleaved || inputs.reads2 != null ? "--detect_adapter_for_pe" : null)
  - position: 6
    prefix: "-h"
    valueFrom: $(inputs.sample_name + ".fastp.html")
  - position: 7
    prefix: "-j"
    valueFrom: $(inputs.sample_name + ".fastp.json")
  - position: 8
    prefix: "-o"
    valueFrom: /tmp/fastp_discard_r1.fastq.gz
  - position: 9
    prefix: "-O"
    valueFrom: |
      $(inputs.reads2 != null || inputs.interleaved ? "/tmp/fastp_discard_r2.fastq.gz" : null)
  - position: 100
    shellQuote: false
    valueFrom: >-
      && detected_r1=\$(sed -n 's/.*"read1_adapter_sequence"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' $(inputs.sample_name).fastp.json)
      && detected_r2=\$(sed -n 's/.*"read2_adapter_sequence"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' $(inputs.sample_name).fastp.json)
      && manual_r1='$(inputs.manual_r1_adapter ? inputs.manual_r1_adapter : "")'
      && manual_r2='$(inputs.manual_r2_adapter ? inputs.manual_r2_adapter : "")'
      && manual_r1=\$(printf '%s' "$manual_r1" | awk '{$1=$1; print}')
      && manual_r2=\$(printf '%s' "$manual_r2" | awk '{$1=$1; print}')
      && if [ "\$(printf '%s' "$manual_r1" | tr '[:upper:]' '[:lower:]')" = "unspecified" ]; then manual_r1=""; fi
      && if [ "\$(printf '%s' "$manual_r2" | tr '[:upper:]' '[:lower:]')" = "unspecified" ]; then manual_r2=""; fi
      && detected_r1_known=false
      && detected_r2_known=false
      && if [ -n "$detected_r1" ] && grep -Fq "$detected_r1 ->" '$(inputs.sample_name).fastp.html'; then detected_r1_known=true; fi
      && if [ -n "$(inputs.interleaved || inputs.reads2 != null ? "paired" : "")" ] && [ -n "$detected_r2" ] && grep -Fq "$detected_r2 ->" '$(inputs.sample_name).fastp.html'; then detected_r2_known=true; fi
      && : > r1_adapter.txt
      && : > r2_adapter.txt
      && printf 'false\n' > run_cutadapt.txt
      && if [ -n "$manual_r1" ]; then printf '%s\n' "$manual_r1" > r1_adapter.txt; elif [ "$detected_r1_known" = true ]; then printf '%s\n' "$detected_r1" > r1_adapter.txt; fi
      && if [ -n "$(inputs.interleaved || inputs.reads2 != null ? "paired" : "")" ]; then if [ -n "$manual_r2" ]; then printf '%s\n' "$manual_r2" > r2_adapter.txt; elif [ "$detected_r2_known" = true ]; then printf '%s\n' "$detected_r2" > r2_adapter.txt; fi; fi
      && if [ -s r1_adapter.txt ] || [ -s r2_adapter.txt ]; then printf 'true\n' > run_cutadapt.txt; fi

outputs:
  fastp_json:
    type: File
    doc: "fastp JSON report with detected adapter sequences and QC metrics"
    outputBinding:
      glob: $(inputs.sample_name).fastp.json
  fastp_html:
    type: File
    doc: "fastp HTML report"
    outputBinding:
      glob: $(inputs.sample_name).fastp.html
  r1_adapter:
    type: 'string?'
    doc: "Adapter selected for R1 trimming after manual override and fastp safeguards"
    outputBinding:
      glob: r1_adapter.txt
      loadContents: true
      outputEval: |
        ${
          var adapter = self[0].contents.replace(/\u0000/g, "").trim();
          return adapter && adapter.toLowerCase() !== "unspecified" ? adapter : null;
        }
  r2_adapter:
    type: 'string?'
    doc: "Adapter selected for R2 trimming after manual override and fastp safeguards"
    outputBinding:
      glob: r2_adapter.txt
      loadContents: true
      outputEval: |
        ${
          var adapter = self[0].contents.replace(/\u0000/g, "").trim();
          return adapter && adapter.toLowerCase() !== "unspecified" ? adapter : null;
        }
  run_cutadapt:
    type: boolean
    doc: "Whether cutadapt should run based on manual adapters or fastp safeguards"
    outputBinding:
      glob: run_cutadapt.txt
      loadContents: true
      outputEval: $(self[0].contents.trim() == "true")
