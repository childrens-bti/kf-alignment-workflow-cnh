cwlVersion: v1.0
class: CommandLineTool
id: sambamba_index
requirements:
  - class: ShellCommandRequirement
  - class: ResourceRequirement
    coresMin: |-
      ${
          if (inputs.num_of_threads) {

              return inputs.num_of_threads

          } else {

              return 1
          }

      }
  - class: DockerRequirement
    dockerPull: 'images.sbgenomics.com/bogdang/sambamba:0.6.3'
  - class: InitialWorkDirRequirement
    listing: []
  - class: InlineJavascriptRequirement
    expressionLib:
      - |-
        var updateMetadata = function(file, key, value) {
            file['metadata'][key] = value;
            return file;
        };


        var setMetadata = function(file, metadata) {
            if (!('metadata' in file))
                file['metadata'] = metadata;
            else {
                for (var key in metadata) {
                    file['metadata'][key] = metadata[key];
                }
            }
            return file
        };

        var inheritMetadata = function(o1, o2) {
            var commonMetadata = {};
            if (!Array.isArray(o2)) {
                o2 = [o2]
            }
            for (var i = 0; i < o2.length; i++) {
                var example = o2[i]['metadata'];
                for (var key in example) {
                    if (i == 0)
                        commonMetadata[key] = example[key];
                    else {
                        if (!(commonMetadata[key] == example[key])) {
                            delete commonMetadata[key]
                        }
                    }
                }
            }
            if (!Array.isArray(o1)) {
                o1 = setMetadata(o1, commonMetadata)
            } else {
                for (var i = 0; i < o1.length; i++) {
                    o1[i] = setMetadata(o1[i], commonMetadata)
                }
            }
            return o1;
        };

        var toArray = function(file) {
            return [].concat(file);
        };

        var groupBy = function(files, key) {
            var groupedFiles = [];
            var tempDict = {};
            for (var i = 0; i < files.length; i++) {
                var value = files[i]['metadata'][key];
                if (value in tempDict)
                    tempDict[value].push(files[i]);
                else tempDict[value] = [files[i]];
            }
            for (var key in tempDict) {
                groupedFiles.push(tempDict[key]);
            }
            return groupedFiles;
        };

        var orderBy = function(files, key, order) {
            var compareFunction = function(a, b) {
                if (a['metadata'][key].constructor === Number) {
                    return a['metadata'][key] - b['metadata'][key];
                } else {
                    var nameA = a['metadata'][key].toUpperCase();
                    var nameB = b['metadata'][key].toUpperCase();
                    if (nameA < nameB) {
                        return -1;
                    }
                    if (nameA > nameB) {
                        return 1;
                    }
                    return 0;
                }
            };

            files = files.sort(compareFunction);
            if (order == undefined || order == "asc")
                return files;
            else
                return files.reverse();
        };
baseCommand: []
arguments:
  - position: 7
    shellQuote: false
    valueFrom: >-
      mv $(inputs.bam.path) . && /opt/sambamba_0.6.3/sambamba_v0.6.3 index -t
      $(inputs.num_of_threads) $(inputs.bam.basename) $(inputs.bam.nameroot).bai
inputs:
  bam:
    type: File
    label: BAM files
    doc: Input BAM files.
  num_of_threads:
    type: int
    label: Number of threads to use
    doc: Number of threads to use for compression/decompression.
outputs:
  indexed_bam:
    doc: Indexed bam.
    type: File?
    outputBinding:
      glob: '*.bam'
    secondaryFiles:
      - ^.bai
label: Sambamba Index
'sbg:categories':
  - SAM/BAM-Processing
'sbg:license': GNU General Public License v2.0 only
'sbg:links':
  - id: 'http://lomereiter.github.io/sambamba/docs/sambamba-view.html'
    label: Homepage
  - id: 'https://github.com/lomereiter/sambamba'
    label: Source code
  - id: 'https://github.com/lomereiter/sambamba/wiki'
    label: Wiki
  - id: 'https://github.com/lomereiter/sambamba/releases/tag/v0.5.9'
    label: Download
  - id: 'http://lomereiter.github.io/sambamba/docs/sambamba-view.html'
    label: Publication
'sbg:toolAuthor': Artem Tarasov
'sbg:toolkit': Sambamba
'sbg:toolkitVersion': 0.6.3
