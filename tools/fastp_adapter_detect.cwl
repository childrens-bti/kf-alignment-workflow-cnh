cwlVersion: v1.2
class: CommandLineTool
id: fastp_adapter_detect
label: "fastp v0.23.4 Adapter Detection"
doc: |
  Run fastp to detect adapter sequences and produce JSON and HTML QC reports.
  Trimmed reads are discarded (/tmp); only the reports are used downstream.
  Processes up to 1M reads by default.
  - For paired-end input: provide reads2 for separate files, or set interleaved=true for interleaved file.
  - Automatically adds --detect_adapter_for_pe when reads2 is provided or interleaved=true.
  Manual adapters override detected adapters. If no manual R1 adapter is
  provided, detected adapters are selected for cutadapt only when fastp reports
  at least 1% adapter-trimmed bases and the detected adapter sequence starts
  with standard Illumina adapter seeds: AGATCGGA (TruSeq) or CTGTCTCT (Nextera).
  For paired-end/interleaved reads, both R1 and R2 must pass validation.
  Otherwise empty adapter files are emitted and cutadapt is skipped downstream.
requirements:
  - class: ShellCommandRequirement
  - class: DockerRequirement
    dockerPull: 'quay.io/biocontainers/fastp:0.23.4--h5f740d0_0'
  - class: InlineJavascriptRequirement
  - class: ResourceRequirement
    coresMin: $(inputs.threads)
    ramMin: 4000

baseCommand: [fastp]

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
      $(inputs.reads2 != null ? "/tmp/fastp_discard_r2.fastq.gz" : null)
  - position: 100
    shellQuote: false
    valueFrom: >-
      && detected_r1=\$(sed -n 's/.*"read1_adapter_sequence"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' $(inputs.sample_name).fastp.json)
      && detected_r2=\$(sed -n 's/.*"read2_adapter_sequence"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' $(inputs.sample_name).fastp.json)
      && adapter_trimmed_bases=\$(awk '/"adapter_trimmed_bases"/ {gsub(/[^0-9]/, "", $0); print; exit}' $(inputs.sample_name).fastp.json)
      && total_bases=\$(awk '/"before_filtering"/ {in_before=1} in_before && /"total_bases"/ {gsub(/[^0-9]/, "", $0); print; exit}' $(inputs.sample_name).fastp.json)
      && adapter_pct=\$(awk -v trimmed="$adapter_trimmed_bases" -v total="$total_bases" 'BEGIN {if (total > 0) printf "%.6f", 100 * trimmed / total; else print "0"}')
      && manual_r1='$(inputs.manual_r1_adapter ? inputs.manual_r1_adapter : "")'
      && manual_r2='$(inputs.manual_r2_adapter ? inputs.manual_r2_adapter : "")'
      && manual_r1=\$(printf '%s' "$manual_r1" | awk '{$1=$1; print}')
      && manual_r2=\$(printf '%s' "$manual_r2" | awk '{$1=$1; print}')
      && if [ "\$(printf '%s' "$manual_r1" | tr '[:upper:]' '[:lower:]')" = "unspecified" ]; then manual_r1=""; fi
      && if [ "\$(printf '%s' "$manual_r2" | tr '[:upper:]' '[:lower:]')" = "unspecified" ]; then manual_r2=""; fi
      && adapter_pct_ok=false
      && detected_adapters_ok=false
      && if awk -v pct="$adapter_pct" 'BEGIN {exit pct < 1.0}'; then adapter_pct_ok=true; fi
      && if printf '%s' "$detected_r1" | grep -qE '^(AGATCGGA|CTGTCTCT)' && { [ -z "$(inputs.interleaved || inputs.reads2 != null ? "paired" : "")" ] || printf '%s' "$detected_r2" | grep -qE '^(AGATCGGA|CTGTCTCT)'; }; then detected_adapters_ok=true; fi
      && : > r1_adapter.txt
      && : > r2_adapter.txt
      && printf 'false\n' > run_cutadapt.txt
      && if [ -n "$manual_r1" ]; then printf '%s\n' "$manual_r1" > r1_adapter.txt; printf '%s\n' "$manual_r2" > r2_adapter.txt; printf 'true\n' > run_cutadapt.txt; elif [ "$adapter_pct_ok" = true ] && [ "$detected_adapters_ok" = true ]; then printf '%s\n' "$detected_r1" > r1_adapter.txt; printf '%s\n' "$detected_r2" > r2_adapter.txt; printf 'true\n' > run_cutadapt.txt; fi

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
