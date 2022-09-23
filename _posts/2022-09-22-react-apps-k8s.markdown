---
layout: post
title: "Hosting a React app  on Kubernetes"
tags:
 - work
 - kubernetes
 - docker
 - javascript
 - react
---
I have been working towards migrating a bunch of legacy applications off of elastic beanstalk onto a kubernetes infrastructure.
At Begin we use [KoPS](https://kops.sigs.k8s.io/) to manage different Kubernetes clusters, and on them we run a variety of
different tech stacks. We use a combination of AWS Secret Store and K8s configmaps to manage variables that get injected to the
applications(maybe I'll write about that someday) but it's fairly straight forward to manage.

One group of the recent applications I was migrating were just static [React](https://reactjs.org/) apps
that was running on an Apache/PHP Beanstalk. I didn't realize the full configuration of the app at the time, so I started out
by simply configuring the app to inject the environment variables at startup time, and then running [`react-scripts build`](https://create-react-app.dev/docs/available-scripts/#npm-run-build)
and then serving that via nginx in a container running on my cluster. This allowed us to use a single container to run in both dev/test and prod since it compiled the code at boot time and injected the necessary vars.

## The Problems
At first this worked. In our dev and test environments everything seemed fine, and while there was some additional tuning we could do to tell K8s to wait for the compilation to finish before serving traffic, there wasn't much else to it.

*INTRODUCING* Production
Then we went to production. Up until now our team had been small and I had just been running a single replica for both the dev and test deployments. When we went to production I bumped that up to 3 just to have some additional redudency, and heres where I discovered the problem.

**CAVEAT** I'm not a react or a javascript dev so I'm making a lot of assumptions based on the outcomes, but if I'm way off base please [contact me](mailto:kmartinix@gmail.com) **CAVEAT OVER**

We started immedietely seeing a lot of 404s on requests which  was odd because I could see all the files there. Digging further in to the requests I could see each request was attempting to load a different sha of the javascript. That's when I looked at the different containers
![container-shas](/images/react-compiled.png)
I could see each container had a different set of compiled assets, even though the code was the same! I did [some reading](https://create-react-app.dev/docs/production-build) on how react creates those files and didn't get a lot of conclusive information, but it does seem that the ENV vars get sorted randomly in the files and that changes the contents.
After coming to this conclusion I had to do some re-architecting on what our direction was. I knew long term we should be
hosting static websites via S3 and a CDN(Cloudfront/Fastly etc.) but didn't have the bandwidth to get the teams set up for that
so we looked at what we could do in K8s to compile once, then share the code among X number of webservers.

## The ~Workaround~ Solution (for now)
I decided using a Job in Kubernetes would be a simple soution to compile the code, and then the running containers themselves
would just need to basically be nginx serving the static code. This basically worked out to using a Job that ran a container using the app code. This injected the ENV like before,  ran `react-scripts build` like before, and then just zipped up the contents and stored them on S3. I set some additional variables at deploy time to denote the deployed  branch, env, etc.

I chose S3 because the eventual goal is to just have that be the destination - compile the assets,  store them on S3, serve them on S3. Someday.

Then my deployment was a custom nginx container that I have a script that pulls my packaged file off S3, and serves it up. The only trick was waiting for the compile to complete before attempting to pull the new code. I discovered [k8s-wait-for](https://github.com/groundnuty/k8s-wait-for) which I configured as a initContainer to pend until the compilation is complete. Then when Nginx starts it can easily pull the assets!

## Other notes
* Because I'm using Kops, I [configured it's OIDC provider](https://dev.to/olemarkus/irsa-support-for-kops-1doe) to configure a ServiceAccount with permissions to write to my S3 bucket.
* k8s-wait-for needs permission to examine objects. There needs to be a ServiceAccount/Role/Rolebinding granding the appropriate permissions
