// Developer-only check of exported animation: exposure, temporal change, repeats.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const report = {};
const args=process.argv.slice(2),directories=[];
let skipFirst=0,skipLast=0;
for(let i=0;i<args.length;i++) {
  if(args[i]==='--skip-first')skipFirst=Number(args[++i]);
  else if(args[i]==='--skip-last')skipLast=Number(args[++i]);
  else directories.push(args[i]);
}
if(!Number.isInteger(skipFirst)||!Number.isInteger(skipLast)||skipFirst<0||skipLast<0)
  throw Error('Frame skips must be nonnegative integers');
for (const directory of directories) {
  const files = fs.readdirSync(directory).filter(f => /^frame\d+\.bmp$/.test(f))
    .sort((a,b)=>Number(a.slice(5,-4))-Number(b.slice(5,-4)));
  let previous, previousMean, minMean=255, maxMean=0, maxMeanStep=0;
  let maxDifference=0, sumDifference=0, maxDifferenceFrame=0, minLit=1, maxWhite=0;
  let minLitFrame=0,maxWhiteFrame=0,maxMeanStepFrame=0;
  const hashes = new Set();
  for (const [frame, file] of files.entries()) {
    const bmp = fs.readFileSync(path.join(directory,file));
    const pixels=bmp.subarray(bmp.readUInt32LE(10));
    const width=bmp.readInt32LE(18), height=Math.abs(bmp.readInt32LE(22));
    if(bmp.readUInt16LE(28)!==32 || pixels.length!==width*height*4) throw Error('Unexpected BMP format');
    hashes.add(crypto.createHash('sha256').update(pixels).digest('hex'));
    let sum=0, difference=0, lit=0, white=0;
    for(let i=0;i<pixels.length;i+=4) {
      const value=.2126*pixels[i+2]+.7152*pixels[i+1]+.0722*pixels[i];
      sum+=value; if(value>10)lit++; if(value>245)white++;
      if(previous) difference+=Math.abs(pixels[i]-previous[i])+Math.abs(pixels[i+1]-previous[i+1])+Math.abs(pixels[i+2]-previous[i+2]);
    }
    const count=width*height, mean=sum/count, change=difference/(count*3);
    minMean=Math.min(minMean,mean); maxMean=Math.max(maxMean,mean);
    // A complete-show capture has intentional opening/closing exposure ramps.
    // Only those explicitly excluded endcaps bypass the blank-frame check.
    if(frame>=skipFirst&&frame<files.length-skipLast) {
      if(lit/count<minLit){minLit=lit/count;minLitFrame=frame;}
      if(white/count>maxWhite){maxWhite=white/count;maxWhiteFrame=frame;}
    }
    if(previousMean!==undefined&&Math.abs(mean-previousMean)>maxMeanStep){maxMeanStep=Math.abs(mean-previousMean);maxMeanStepFrame=frame;}
    if(change>maxDifference){maxDifference=change;maxDifferenceFrame=frame;}
    sumDifference+=change; previous=pixels; previousMean=mean;
  }
  if(files.length<=skipFirst+skipLast || minLit<.01 || maxWhite>.95)
    throw Error(`Blank or nearly white frame in ${directory}: minLit=${minLit} at ${minLitFrame}, maxWhite=${maxWhite} at ${maxWhiteFrame}`);
  report[path.basename(directory)]={frames:files.length,checkedExposureFrames:files.length-skipFirst-skipLast,uniqueFrames:hashes.size,minMean,maxMean,maxMeanStep,maxMeanStepFrame,minLit,minLitFrame,maxWhite,maxWhiteFrame,meanDifference:sumDifference/Math.max(1,files.length-1),maxDifference,maxDifferenceFrame};
}
process.stdout.write(JSON.stringify(report,null,2)+'\n');
